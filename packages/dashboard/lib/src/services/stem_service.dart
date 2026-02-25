import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_cli/stem_cli.dart';
import 'package:stem_dashboard/src/config/config.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

/// Contract for dashboard services that load queue and worker data.
abstract class DashboardDataSource {
  /// Fetches summaries for all known queues.
  Future<List<QueueSummary>> fetchQueueSummaries();

  /// Fetches current worker status snapshots.
  Future<List<WorkerStatus>> fetchWorkerStatuses();

  /// Fetches persisted task statuses for observability views.
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatuses({
    TaskState? state,
    String? queue,
    int limit = 100,
    int offset = 0,
  });

  /// Fetches a single task status by [taskId].
  Future<DashboardTaskStatusEntry?> fetchTaskStatus(String taskId);

  /// Fetches statuses belonging to a workflow [runId].
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatusesForRun(
    String runId, {
    int limit = 200,
  });

  /// Fetches persisted workflow run snapshot, if a workflow store is available.
  Future<DashboardWorkflowRunSnapshot?> fetchWorkflowRun(String runId);

  /// Fetches persisted workflow checkpoints, if a workflow store is available.
  Future<List<DashboardWorkflowStepSnapshot>> fetchWorkflowSteps(String runId);

  /// Enqueues a task request through the backing broker.
  Future<void> enqueueTask(EnqueueRequest request);

  /// Replays dead letters for [queue].
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  });

  /// Replays a specific dead-letter task by [taskId].
  ///
  /// Returns `true` when the entry was found and replayed.
  Future<bool> replayTaskById(String taskId, {String? queue});

  /// Requests revocation for [taskId].
  ///
  /// Returns `true` when a revoke store is configured and the request is saved.
  Future<bool> revokeTask(
    String taskId, {
    bool terminate = false,
    String? reason,
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
    WorkflowStore? workflowStore,
    RevokeStore? revokeStore,
    Future<void> Function()? disposeContext,
    Future<_DashboardRuntimeContext> Function()? reloadRuntimeContext,
    bool ownsWorkflowStore = false,
  }) : _config = config,
       _namespace = config.namespace,
       _signer = PayloadSigner.maybe(config.stem.signing),
       _broker = broker,
       _backend = backend,
       _workflowStore = workflowStore,
       _revokeStore = revokeStore,
       _disposeContext = disposeContext,
       _reloadRuntimeContext = reloadRuntimeContext,
       _ownsWorkflowStore = ownsWorkflowStore;

  final DashboardConfig _config;
  final String _namespace;
  final PayloadSigner? _signer;
  Broker _broker;
  ResultBackend? _backend;
  final WorkflowStore? _workflowStore;
  RevokeStore? _revokeStore;
  Future<void> Function()? _disposeContext;
  final Future<_DashboardRuntimeContext> Function()? _reloadRuntimeContext;
  Future<void>? _runtimeReconnectFuture;
  Future<void> _runtimeOperationQueue = Future.value();
  final bool _ownsWorkflowStore;
  var _closed = false;

  /// Creates a dashboard service using [config].
  ///
  /// Uses [createDefaultContext] to set up broker and backend from environment.
  static Future<StemDashboardService> connect(DashboardConfig config) async {
    final runtimeContext = await _createRuntimeContext(config);

    final workflowStore = await _connectWorkflowStore(
      config.environment['STEM_WORKFLOW_STORE_URL'],
      namespace: _resolveWorkflowNamespace(config),
      tls: config.tls,
    );

    return StemDashboardService._(
      config: config,
      broker: runtimeContext.broker,
      backend: runtimeContext.backend,
      workflowStore: workflowStore,
      revokeStore: runtimeContext.revokeStore,
      disposeContext: runtimeContext.dispose,
      reloadRuntimeContext: () => _createRuntimeContext(config),
      ownsWorkflowStore: true,
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
    WorkflowStore? workflowStore,
    RevokeStore? revokeStore,
  }) async {
    return StemDashboardService._(
      config: config,
      broker: broker,
      backend: backend,
      workflowStore: workflowStore,
      revokeStore: revokeStore,
    );
  }

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    try {
      return await _withRuntimeReconnectRetry(_fetchQueueSummariesImpl);
    } on Object catch (error, stack) {
      _logReadFailure('fetchQueueSummaries', error, stack);
      return const [];
    }
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async {
    try {
      final heartbeats = await _withRuntimeReconnectRetry(() async {
        final backend = _backend;
        if (backend == null) return const <WorkerHeartbeat>[];
        return backend.listWorkerHeartbeats();
      });
      return heartbeats.map(WorkerStatus.fromHeartbeat).toList(growable: false)
        ..sort((a, b) => a.workerId.compareTo(b.workerId));
    } on Object catch (error, stack) {
      _logReadFailure('fetchWorkerStatuses', error, stack);
      return const [];
    }
  }

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatuses({
    TaskState? state,
    String? queue,
    int limit = 100,
    int offset = 0,
  }) async {
    final resolvedQueue = queue?.trim();
    final boundedLimit = limit.clamp(1, 500);
    final boundedOffset = offset < 0 ? 0 : offset;
    try {
      final page = await _withRuntimeReconnectRetry(() async {
        final backend = _backend;
        if (backend == null) {
          return const TaskStatusPage(items: []);
        }
        return backend.listTaskStatuses(
          TaskStatusListRequest(
            state: state,
            queue: resolvedQueue == null || resolvedQueue.isEmpty
                ? null
                : resolvedQueue,
            limit: boundedLimit,
            offset: boundedOffset,
          ),
        );
      });
      return page.items
          .map(DashboardTaskStatusEntry.fromRecord)
          .toList(growable: false);
    } on Object catch (error, stack) {
      _logReadFailure('fetchTaskStatuses', error, stack);
      return const [];
    }
  }

  @override
  Future<DashboardTaskStatusEntry?> fetchTaskStatus(String taskId) async {
    final trimmed = taskId.trim();
    if (trimmed.isEmpty) return null;

    try {
      final record = await _findTaskStatusRecord(trimmed);
      if (record != null) {
        return DashboardTaskStatusEntry.fromRecord(record);
      }
      final backend = _backend;
      if (backend == null) return null;
      final status = await backend.get(trimmed);
      if (status == null) {
        return null;
      }
      return DashboardTaskStatusEntry.fromStatus(status);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatusesForRun(
    String runId, {
    int limit = 200,
  }) async {
    final trimmed = runId.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final page = await _withRuntimeReconnectRetry(() async {
        final backend = _backend;
        if (backend == null) {
          return const TaskStatusPage(items: []);
        }
        return backend.listTaskStatuses(
          TaskStatusListRequest(
            meta: {'stem.workflow.runId': trimmed},
            limit: limit.clamp(1, 500),
          ),
        );
      });
      return page.items
          .map(DashboardTaskStatusEntry.fromRecord)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  @override
  Future<DashboardWorkflowRunSnapshot?> fetchWorkflowRun(String runId) async {
    final store = _workflowStore;
    if (store == null) return null;

    final trimmed = runId.trim();
    if (trimmed.isEmpty) return null;

    try {
      final run = await store.get(trimmed);
      if (run == null) return null;
      return DashboardWorkflowRunSnapshot.fromRunState(run);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<DashboardWorkflowStepSnapshot>> fetchWorkflowSteps(
    String runId,
  ) async {
    final store = _workflowStore;
    if (store == null) return const [];

    final trimmed = runId.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final steps = await store.listSteps(trimmed);
      return steps
          .map(DashboardWorkflowStepSnapshot.fromEntry)
          .toList(growable: false)
        ..sort((a, b) => a.position.compareTo(b.position));
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
    await _publishEnvelope(envelope);
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) async {
    final bounded = limit.clamp(1, 500);
    return _withRuntimeReconnectRetry(
      () => _broker.replayDeadLetters(queue, limit: bounded, dryRun: dryRun),
    );
  }

  @override
  Future<bool> replayTaskById(String taskId, {String? queue}) async {
    final trimmedTask = taskId.trim();
    if (trimmedTask.isEmpty) return false;

    final resolvedQueue = await _resolveReplayQueue(trimmedTask, queue: queue);
    if (resolvedQueue == null) {
      return false;
    }

    final deadLetter = await _withRuntimeReconnectRetry(
      () => _broker.getDeadLetter(resolvedQueue, trimmedTask),
    );
    if (deadLetter == null) {
      return false;
    }

    final now = stemNow().toUtc();
    final original = deadLetter.envelope;
    final replayMeta = Map<String, Object?>.from(original.meta)
      ..['source'] = 'dashboard'
      ..['dashboard.replayFromTaskId'] = trimmedTask
      ..['dashboard.replayedAt'] = now.toIso8601String();
    final replay = original.copyWith(
      id: generateEnvelopeId(),
      attempt: 0,
      enqueuedAt: now,
      meta: replayMeta,
    );
    await _publishEnvelope(replay);

    final backend = _backend;
    if (backend != null) {
      final queuedMeta = <String, Object?>{
        'queue': replay.queue,
        'task': replay.name,
        ...replayMeta,
      };
      await backend.set(
        replay.id,
        TaskState.queued,
        attempt: 0,
        meta: queuedMeta,
      );
    }
    return true;
  }

  @override
  Future<bool> revokeTask(
    String taskId, {
    bool terminate = false,
    String? reason,
  }) async {
    final trimmedTask = taskId.trim();
    if (trimmedTask.isEmpty) return false;

    final now = stemNow().toUtc();
    final trimmedReason = reason?.trim();
    final entry = RevokeEntry(
      namespace: _namespace,
      taskId: trimmedTask,
      version: generateRevokeVersion(),
      issuedAt: now,
      terminate: terminate,
      reason: trimmedReason == null || trimmedReason.isEmpty
          ? null
          : trimmedReason,
      requestedBy: 'dashboard',
    );
    try {
      final store = _revokeStore;
      if (store == null) {
        return false;
      }
      await store.upsertAll([entry]);
      return true;
    } on Object {
      return false;
    }
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

    final now = stemNow().toUtc();
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
      await _publishEnvelope(envelope);
    }

    final expectedReplies = command.targets.isEmpty
        ? null
        : command.targets.length;
    final prefetch = expectedReplies == null ? 8 : expectedReplies.clamp(1, 32);

    final subscription = await _withRuntimeReconnectRetry<Stream<Delivery>>(
      () async {
        return _broker.consume(
          RoutingSubscription.singleQueue(replyQueue),
          consumerGroup: _controlConsumerGroup,
          consumerName: 'dashboard-${command.requestId}',
          prefetch: prefetch,
        );
      },
    );

    final iterator = StreamIterator<Delivery>(subscription);
    final replies = <ControlReplyMessage>[];
    final deadline = stemNow().add(timeout);

    try {
      while (true) {
        final now = stemNow();
        final remaining = deadline.difference(now);
        if (remaining <= Duration.zero) {
          break;
        }
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
          await _withRuntimeReconnectRetry(() => _broker.ack(delivery));
        } on Object {
          await _withRuntimeReconnectRetry(
            () => _broker.nack(delivery, requeue: false),
          );
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
    if (_closed) return;
    _closed = true;

    if (_ownsWorkflowStore) {
      await _disposeWorkflowStore(_workflowStore);
    }

    await _disposeRuntimeContext();
  }

  Future<List<QueueSummary>> _fetchQueueSummariesImpl() async {
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

  Future<T> _withRuntimeReconnectRetry<T>(Future<T> Function() action) {
    return _serializeRuntimeAccess(() async {
      try {
        return await action();
      } on Object catch (error) {
        final recovered = await _recoverRuntimeContextIfNeeded(error);
        if (!recovered) {
          rethrow;
        }
        return action();
      }
    });
  }

  Future<bool> _recoverRuntimeContextIfNeeded(Object error) async {
    if (_closed || !_isRecoverableConnectionError(error)) {
      return false;
    }

    final reloadRuntimeContext = _reloadRuntimeContext;
    if (reloadRuntimeContext == null) {
      return false;
    }

    try {
      await _reconnectRuntimeContext(reloadRuntimeContext);
      return true;
    } on Object {
      return false;
    }
  }

  bool _isRecoverableConnectionError(Object error) {
    if (error is SocketException ||
        error is IOException ||
        error is StateError) {
      return true;
    }
    final message = '$error'.toLowerCase();
    return message.contains('streamsink is closed') ||
        message.contains('stream is closed') ||
        message.contains('connection closed') ||
        message.contains('not connected') ||
        message.contains('connection refused') ||
        message.contains('socket is closed') ||
        message.contains('broken pipe') ||
        message.contains('timed out') ||
        message.contains('connection reset');
  }

  Future<T> _serializeRuntimeAccess<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _runtimeOperationQueue = _runtimeOperationQueue.catchError((_) {}).then((
      _,
    ) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _logReadFailure(String operation, Object error, StackTrace stack) {
    stemLogger.warning(
      'Dashboard data read failed',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'service',
        fields: {
          'operation': operation,
          'error': '$error',
          'stack': '$stack',
        },
      ),
    );
  }

  Future<void> _reconnectRuntimeContext(
    Future<_DashboardRuntimeContext> Function() reloadRuntimeContext,
  ) async {
    if (_runtimeReconnectFuture != null) {
      return _runtimeReconnectFuture!;
    }
    final completer = Completer<void>();
    _runtimeReconnectFuture = completer.future;
    try {
      final nextContext = await reloadRuntimeContext();
      final previousDispose = _disposeContext;
      _broker = nextContext.broker;
      _backend = nextContext.backend;
      _revokeStore = nextContext.revokeStore;
      _disposeContext = nextContext.dispose;
      if (previousDispose != null) {
        try {
          await previousDispose();
        } on Object {
          // Ignore disposal failures while recovering from connection errors.
        }
      }
      completer.complete();
    } on Object catch (error, stack) {
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _runtimeReconnectFuture = null;
    }
  }

  Future<void> _disposeRuntimeContext() async {
    final disposeContext = _disposeContext;
    _disposeContext = null;
    if (disposeContext != null) {
      await disposeContext();
    }
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
      await _withRuntimeReconnectRetry(() => _broker.purge(queue));
    } on Object {
      // Some brokers may not support purge; ignore failures.
    }
  }

  Future<void> _publishEnvelope(Envelope envelope) async {
    final signer = _signer;
    final payload = signer == null ? envelope : await signer.sign(envelope);
    await _withRuntimeReconnectRetry(() => _broker.publish(payload));
  }

  Future<TaskStatusRecord?> _findTaskStatusRecord(String taskId) async {
    final backend = _backend;
    if (backend == null) return null;

    var offset = 0;
    const pageSize = 200;
    const maxPages = 10;

    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await backend.listTaskStatuses(
        TaskStatusListRequest(limit: pageSize, offset: offset),
      );
      for (final item in page.items) {
        if (item.status.id == taskId) {
          return item;
        }
      }
      final nextOffset = page.nextOffset;
      if (nextOffset == null) {
        break;
      }
      offset = nextOffset;
    }
    return null;
  }

  Future<String?> _resolveReplayQueue(
    String taskId, {
    String? queue,
  }) async {
    final explicit = queue?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final status = await fetchTaskStatus(taskId);
    final statusQueue = status?.queue.trim();
    if (statusQueue != null && statusQueue.isNotEmpty) {
      return statusQueue;
    }

    final queues = await _discoverQueues();
    for (final candidate in queues) {
      final entry = await _broker.getDeadLetter(candidate, taskId);
      if (entry != null) {
        return candidate;
      }
    }
    return null;
  }

  static String _resolveWorkflowNamespace(DashboardConfig config) {
    final raw = config.environment['STEM_WORKFLOW_NAMESPACE']?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return config.namespace;
  }

  static Future<WorkflowStore?> _connectWorkflowStore(
    String? url, {
    required String namespace,
    required TlsConfig tls,
  }) async {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.parse(trimmed);
    switch (uri.scheme) {
      case 'redis':
      case 'rediss':
        return RedisWorkflowStore.connect(
          trimmed,
          namespace: namespace,
          tls: tls,
        );
      case 'postgres':
      case 'postgresql':
      case 'postgresql+ssl':
      case 'postgres+ssl':
        return PostgresWorkflowStore.connect(
          trimmed,
          namespace: namespace,
          applicationName: 'stem-dashboard-workflow',
          tls: tls,
        );
      case 'sqlite':
        final path = uri.path.isNotEmpty ? uri.path : 'workflow.sqlite';
        return SqliteWorkflowStore.open(File(path));
      case 'file':
        return SqliteWorkflowStore.open(File(uri.toFilePath()));
      case 'memory':
        return InMemoryWorkflowStore();
      default:
        return null;
    }
  }

  static Future<void> _disposeWorkflowStore(WorkflowStore? store) async {
    if (store is RedisWorkflowStore) {
      await store.close();
      return;
    }
    if (store is PostgresWorkflowStore) {
      await store.close();
      return;
    }
    if (store is SqliteWorkflowStore) {
      await store.close();
    }
  }

  static Future<_DashboardRuntimeContext> _createRuntimeContext(
    DashboardConfig config,
  ) async {
    final context = await createDefaultContext(
      environment: Map<String, String>.from(config.environment),
    );
    return _DashboardRuntimeContext(
      broker: context.broker,
      backend: context.backend,
      revokeStore: context.revokeStore,
      dispose: context.dispose,
    );
  }

  static const _controlConsumerGroup = 'stem-dashboard-control';
}

class _DashboardRuntimeContext {
  const _DashboardRuntimeContext({
    required this.broker,
    required this.backend,
    required this.revokeStore,
    required this.dispose,
  });

  final Broker broker;
  final ResultBackend? backend;
  final RevokeStore? revokeStore;
  final Future<void> Function() dispose;
}
