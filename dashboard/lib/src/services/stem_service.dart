import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/cli/utilities.dart';

import '../config/config.dart';
import '../stem/control_messages.dart';
import 'models.dart';

abstract class DashboardDataSource {
  Future<List<QueueSummary>> fetchQueueSummaries();
  Future<List<WorkerStatus>> fetchWorkerStatuses();
  Future<void> enqueueTask(EnqueueRequest request);
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  });
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout,
  });
  Future<void> close();
}

class StemDashboardService implements DashboardDataSource {
  StemDashboardService._({required DashboardConfig config})
    : _config = config,
      _namespace = config.namespace,
      _environment = Map<String, String>.from(config.environment);

  final DashboardConfig _config;
  final String _namespace;
  final Map<String, String> _environment;

  static Future<StemDashboardService> connect(DashboardConfig config) async =>
      StemDashboardService._(config: config);

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() => _withContext((ctx) async {
    final broker = ctx.broker;
    final queues = await _discoverQueues(ctx);
    final summaries = <QueueSummary>[];
    for (final queue in queues) {
      final pending = await broker.pendingCount(queue) ?? 0;
      final inflight = await broker.inflightCount(queue) ?? 0;
      final dead = await _deadLetterCount(broker, queue);
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
  });

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() => _withContext((ctx) async {
    final backend = ctx.backend;
    if (backend == null) return const [];
    try {
      final heartbeats = await backend.listWorkerHeartbeats();
      final statuses =
          heartbeats.map(WorkerStatus.fromHeartbeat).toList(growable: false)
            ..sort((a, b) => a.workerId.compareTo(b.workerId));
      return statuses;
    } catch (_) {
      return const [];
    }
  });

  @override
  Future<void> enqueueTask(EnqueueRequest request) => _withContext((ctx) async {
    final envelope = Envelope(
      id: generateEnvelopeId(),
      name: request.task,
      args: request.args,
      queue: request.queue,
      priority: request.priority,
      maxRetries: request.maxRetries,
      meta: const {'source': 'dashboard'},
    );
    await ctx.broker.publish(envelope);
  });

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) => _withContext((ctx) async {
    final bounded = limit.clamp(1, 500).toInt();
    return ctx.broker.replayDeadLetters(queue, limit: bounded, dryRun: dryRun);
  });

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) => _withContext((ctx) async {
    final broker = ctx.broker;
    final replyQueue = ControlQueueNames.reply(_namespace, command.requestId);
    await _purgeQueue(broker, replyQueue);

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
      await broker.publish(envelope);
    }

    final expectedReplies = command.targets.isEmpty
        ? null
        : command.targets.length;
    final prefetch = expectedReplies == null ? 8 : expectedReplies.clamp(1, 32);

    final subscription = broker.consume(
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
          await broker.ack(delivery);
        } catch (_) {
          await broker.nack(delivery, requeue: false);
        }

        if (expectedReplies != null && replies.length >= expectedReplies) {
          break;
        }
      }
    } finally {
      await iterator.cancel();
      await _purgeQueue(broker, replyQueue);
    }

    return replies;
  });

  @override
  Future<void> close() async {
    // No persistent connections to close; contexts are per-call.
  }

  Future<T> _withContext<T>(Future<T> Function(CliContext ctx) action) async {
    final ctx = await createDefaultContext(environment: _environment);
    try {
      // Ensure primary queue has a consumer group before we read metrics.
      await _ensureGroupExists(ctx);
      return await action(ctx);
    } finally {
      await ctx.dispose();
    }
  }

  Future<Set<String>> _discoverQueues(CliContext ctx) async {
    final names = <String>{_config.stem.defaultQueue};
    names.addAll(_config.stem.workerQueues);
    names.addAll(_config.routing.config.queues.keys);

    final backend = ctx.backend;
    if (backend != null) {
      try {
        final heartbeats = await backend.listWorkerHeartbeats();
        for (final heartbeat in heartbeats) {
          for (final queue in heartbeat.queues) {
            names.add(queue.name);
          }
        }
      } catch (_) {
        // Ignore discovery errors from backend.
      }
    }

    names.removeWhere((value) => value.trim().isEmpty);
    if (names.isEmpty) {
      names.add(_config.stem.defaultQueue);
    }
    return names;
  }

  Future<int> _deadLetterCount(Broker broker, String queue) async {
    var total = 0;
    var offset = 0;
    const pageSize = 200;
    const maxIterations = 50;

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final page = await broker.listDeadLetters(
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

  Future<void> _ensureGroupExists(CliContext ctx) async {
    final broker = ctx.broker;
    if (broker is RedisStreamsBroker) {
      // Touch the default queue to force group creation if it doesn't exist.
      await broker.pendingCount(_config.stem.defaultQueue);
    }
  }

  Future<void> _purgeQueue(Broker broker, String queue) async {
    try {
      await broker.purge(queue);
    } catch (_) {
      // Some brokers may not support purge; ignore failures.
    }
  }

  static const _controlConsumerGroup = 'stem-dashboard-control';
}
