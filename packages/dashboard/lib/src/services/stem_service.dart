import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_cli/stem_cli.dart';

import 'package:stem_dashboard/src/config/config.dart';
import 'package:stem_dashboard/src/services/models.dart';

/// Contract for dashboard services that load queue and worker data.
abstract class DashboardDataSource {
  /// Fetches summaries for all known queues.
  Future<List<QueueSummary>> fetchQueueSummaries();

  /// Fetches current worker status snapshots.
  Future<List<WorkerStatus>> fetchWorkerStatuses();

  /// Enqueues a task request through the backing broker.
  Future<void> enqueueTask(EnqueueRequest request);

  /// Replays dead letters for [queue].
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  });

  /// Sends a control command and returns any replies collected.
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout,
  });

  /// Releases any resources held by the data source.
  Future<void> close();
}

/// Dashboard data source backed by Stem broker and result backend APIs.
class StemDashboardService implements DashboardDataSource {
  StemDashboardService._({
    required DashboardConfig config,
    required Broker broker,
    ResultBackend? backend,
  }) : _config = config,
       _namespace = config.namespace,
       _broker = broker,
       _backend = backend;

  final DashboardConfig _config;
  final String _namespace;
  final Broker _broker;
  final ResultBackend? _backend;

  /// Creates a dashboard service using [config].
  ///
  /// Uses [createDefaultContext] to set up broker and backend from environment.
  static Future<StemDashboardService> connect(DashboardConfig config) async {
    final ctx = await createDefaultContext(
      environment: Map<String, String>.from(config.environment),
    );

    return StemDashboardService._(
      config: config,
      broker: ctx.broker,
      backend: ctx.backend,
    );
  }

  /// Creates a dashboard service with explicit broker and backend instances.
  ///
  /// This is useful for testing or when you already have broker/backend
  /// instances.
  static Future<StemDashboardService> fromInstances({
    required DashboardConfig config,
    required Broker broker,
    ResultBackend? backend,
  }) async {
    return StemDashboardService._(
      config: config,
      broker: broker,
      backend: backend,
    );
  }

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    final queues = await _discoverQueues();
    final summaries = <QueueSummary>[];

    for (final queue in queues) {
      final pending = await _broker.pendingCount(queue) ?? 0;
      final inflight = await _broker.inflightCount(queue) ?? 0;
      final dead = await _deadLetterCount(queue);

      summaries.add(
        QueueSummary(
          queue: queue,
          pending: pending,
          inflight: inflight,
          deadLetters: dead,
        ),
      );
    }

    summaries.sort((a, b) => a.queue.compareTo(b.queue));
    return summaries;
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async {
    final backend = _backend;
    if (backend == null) return const [];

    try {
      final heartbeats = await backend.listWorkerHeartbeats();
      return heartbeats.map(WorkerStatus.fromHeartbeat).toList(growable: false)
        ..sort((a, b) => a.workerId.compareTo(b.workerId));
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {
    final envelope = Envelope(
      id: generateEnvelopeId(),
      name: request.task,
      args: request.args,
      queue: request.queue,
      priority: request.priority,
      maxRetries: request.maxRetries,
      meta: const {'source': 'dashboard'},
    );
    await _broker.publish(envelope);
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) async {
    final bounded = limit.clamp(1, 500);
    return _broker.replayDeadLetters(queue, limit: bounded, dryRun: dryRun);
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final replyQueue = ControlQueueNames.reply(_namespace, command.requestId);
    await _purgeQueue(replyQueue);

    final targets = command.targets.isEmpty
        ? <String>[ControlQueueNames.broadcast(_namespace)]
        : command.targets
              .map((target) => ControlQueueNames.worker(_namespace, target))
              .toList();

    final now = DateTime.now().toUtc();
    for (final queue in targets) {
      final envelope = Envelope(
        id: generateEnvelopeId(),
        name: ControlEnvelopeTypes.command,
        queue: queue,
        args: command.toMap(),
        headers: {
          'stem-control': '1',
          'stem-reply-to': replyQueue,
          'stem-command-source': 'dashboard',
        },
        meta: const {'source': 'dashboard'},
        enqueuedAt: now,
      );
      await _broker.publish(envelope);
    }

    final expectedReplies = command.targets.isEmpty
        ? null
        : command.targets.length;
    final prefetch = expectedReplies == null ? 8 : expectedReplies.clamp(1, 32);

    final subscription = _broker.consume(
      RoutingSubscription.singleQueue(replyQueue),
      consumerGroup: _controlConsumerGroup,
      consumerName: 'dashboard-${command.requestId}',
      prefetch: prefetch,
    );

    final iterator = StreamIterator(subscription);
    final replies = <ControlReplyMessage>[];
    final deadline = DateTime.now().add(timeout);

    try {
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        bool hasNext;
        try {
          hasNext = await iterator.moveNext().timeout(remaining);
        } on TimeoutException {
          break;
        }
        if (!hasNext) break;

        final delivery = iterator.current;
        try {
          final reply = controlReplyFromEnvelope(delivery.envelope);
          replies.add(reply);
          await _broker.ack(delivery);
        } on Object {
          await _broker.nack(delivery, requeue: false);
        }

        if (expectedReplies != null && replies.length >= expectedReplies) {
          break;
        }
      }
    } finally {
      await iterator.cancel();
      await _purgeQueue(replyQueue);
    }

    return replies;
  }

  @override
  Future<void> close() async {
    // Note: The broker and backend will be closed when the context is disposed.
    // Since we got them from createDefaultContext, we don't own their
    // lifecycle.
  }

  Future<Set<String>> _discoverQueues() async {
    final names = <String>{_config.stem.defaultQueue}
      ..addAll(_config.stem.workerQueues)
      ..addAll(_config.routing.config.queues.keys);

    final backend = _backend;
    if (backend != null) {
      try {
        final heartbeats = await backend.listWorkerHeartbeats();
        for (final heartbeat in heartbeats) {
          for (final queue in heartbeat.queues) {
            names.add(queue.name);
          }
          final subscriptions = heartbeat.extras['subscriptions'];
          if (subscriptions is Map) {
            final queues = subscriptions['queues'];
            if (queues is List) {
              for (final entry in queues) {
                final name = entry?.toString().trim();
                if (name != null && name.isNotEmpty) {
                  names.add(name);
                }
              }
            }
          }
        }
      } on Object {
        // Ignore discovery errors from backend.
      }
    }

    names.removeWhere((value) => value.trim().isEmpty);
    if (names.isEmpty) {
      names.add(_config.stem.defaultQueue);
    }
    return names;
  }

  Future<int> _deadLetterCount(String queue) async {
    var total = 0;
    var offset = 0;
    const pageSize = 200;
    const maxIterations = 50;

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final page = await _broker.listDeadLetters(
        queue,
        limit: pageSize,
        offset: offset,
      );
      total += page.entries.length;
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
    }
    return total;
  }

  Future<void> _purgeQueue(String queue) async {
    try {
      await _broker.purge(queue);
    } on Object {
      // Some brokers may not support purge; ignore failures.
    }
  }

  static const _controlConsumerGroup = 'stem-dashboard-control';
}
