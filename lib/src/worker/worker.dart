import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:contextual/contextual.dart';
import 'package:opentelemetry/api.dart' as otel;

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../core/retry.dart';
import '../observability/logging.dart';
import '../observability/metrics.dart';
import '../observability/config.dart';
import '../observability/heartbeat.dart';
import '../observability/heartbeat_transport.dart';
import '../observability/tracing.dart';
import '../core/task_invocation.dart';
import 'isolate_pool.dart';

/// A daemon that consumes tasks from a broker and executes registered handlers.
///
/// Manages task execution with features like concurrency control, rate limiting,
/// retries, heartbeats, and observability. Supports running tasks in isolates
/// for isolation and performance.
///
/// ```dart
/// final worker = Worker(
///   broker: myBroker,
///   registry: myRegistry,
///   backend: myBackend,
/// );
/// await worker.start();
/// ```
class Worker {
  /// Creates a worker instance.
  ///
  /// The [broker] handles message consumption and publishing. The [registry]
  /// provides task handlers. The [backend] stores task results and state.
  /// Optional [rateLimiter] enforces rate limits per task. [middleware] allows
  /// intercepting task lifecycle events. [retryStrategy] determines retry
  /// delays on failure. [queue] specifies the queue to consume from, defaulting
  /// to 'default'. [consumerName] identifies this worker instance. [concurrency]
  /// sets the maximum concurrent tasks, defaulting to the number of processors.
  /// [prefetchMultiplier] scales prefetch count relative to concurrency.
  /// [prefetch] overrides the calculated prefetch count. [heartbeatInterval]
  /// sets the interval for task heartbeats. [workerHeartbeatInterval] sets the
  /// interval for worker-level heartbeats. [heartbeatTransport] handles
  /// heartbeat publishing. [heartbeatNamespace] provides the namespace for
  /// heartbeats. [observability] configures metrics and logging.
  Worker({
    required this.broker,
    required this.registry,
    required this.backend,
    this.rateLimiter,
    this.middleware = const [],
    RetryStrategy? retryStrategy,
    this.queue = 'default',
    this.consumerName,
    int? concurrency,
    int prefetchMultiplier = 2,
    int? prefetch,
    this.heartbeatInterval = const Duration(seconds: 10),
    Duration? workerHeartbeatInterval,
    HeartbeatTransport? heartbeatTransport,
    String heartbeatNamespace = 'stem',
    ObservabilityConfig? observability,
  }) : workerHeartbeatInterval =
           observability?.heartbeatInterval ??
           workerHeartbeatInterval ??
           heartbeatInterval,
       heartbeatTransport =
           heartbeatTransport ?? const NoopHeartbeatTransport(),
       namespace = observability?.namespace ?? heartbeatNamespace,
       concurrency = _normalizeConcurrency(concurrency),
       prefetchMultiplier = math.max(1, prefetchMultiplier),
       prefetch = _calculatePrefetch(
         prefetch,
         _normalizeConcurrency(concurrency),
         math.max(1, prefetchMultiplier),
       ),
       retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy() {
    observability?.applyMetricExporters();
  }

  final Broker broker;
  final TaskRegistry registry;
  final ResultBackend backend;
  final RateLimiter? rateLimiter;
  final List<Middleware> middleware;
  final RetryStrategy retryStrategy;
  final String queue;
  final String? consumerName;
  final int concurrency;
  final int prefetchMultiplier;
  final int prefetch;
  final Duration heartbeatInterval;
  final Duration workerHeartbeatInterval;
  final HeartbeatTransport heartbeatTransport;
  final String namespace;

  final Map<String, Timer> _leaseTimers = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, StreamSubscription<Delivery>> _subscriptions = {};
  final StreamController<WorkerEvent> _events = StreamController.broadcast();
  TaskIsolatePool? _isolatePool;
  Future<TaskIsolatePool>? _poolFuture;

  bool _running = false;
  final Map<String, _ActiveDelivery> _activeDeliveries = {};
  final Map<String, int> _inflightPerQueue = {};
  int _inflight = 0;
  Timer? _workerHeartbeatTimer;
  DateTime? _lastLeaseRenewal;
  int? _lastQueueDepth;

  /// A stream of events emitted during task processing.
  ///
  /// Includes events like task start, completion, failure, and heartbeats.
  Stream<WorkerEvent> get events => _events.stream;

  /// Starts the worker, beginning task consumption and processing.
  ///
  /// Initializes heartbeat loops and subscribes to the queue. Throws if already
  /// running.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _startWorkerHeartbeatLoop();
    _recordInflightGauge();
    unawaited(_publishWorkerHeartbeat());
    final subscription = broker
        .consume(queue, prefetch: prefetch, consumerName: consumerName)
        .listen(
          (delivery) {
            // Fire-and-forget; handler manages its own lifecycle.
            final task = _handle(delivery);
            unawaited(
              task.catchError((Object error, StackTrace stack) {
                _events.add(
                  WorkerEvent(
                    type: WorkerEventType.error,
                    envelope: delivery.envelope,
                    error: error,
                    stackTrace: stack,
                  ),
                );
              }),
            );
          },
          onError: (Object error, StackTrace stack) {
            _events.add(
              WorkerEvent(
                type: WorkerEventType.error,
                error: error,
                stackTrace: stack,
              ),
            );
          },
        );
    _subscriptions[queue] = subscription;
  }

  /// Stops the worker, canceling subscriptions, timers, and cleaning up resources.
  ///
  /// Waits for active tasks to complete before shutting down.
  Future<void> shutdown() async {
    _running = false;
    final pool = _isolatePool;
    _isolatePool = null;
    _poolFuture = null;
    await pool?.dispose();
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();

    for (final timer in _leaseTimers.values) {
      timer.cancel();
    }
    _leaseTimers.clear();

    for (final timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();

    _workerHeartbeatTimer?.cancel();
    _workerHeartbeatTimer = null;
    _activeDeliveries.clear();
    _inflightPerQueue.clear();
    _inflight = 0;
    await heartbeatTransport.close();

    await _events.close();
  }

  Future<void> _handle(Delivery delivery) async {
    final envelope = delivery.envelope;
    final tracer = StemTracer.instance;
    final parentContext = tracer.extractTraceContext(envelope.headers);
    final spanAttributes = [
      otel.Attribute.fromString('stem.task', envelope.name),
      otel.Attribute.fromString('stem.queue', envelope.queue),
    ];

    await tracer.trace(
      'stem.consume',
      () async {
        final handler = registry.resolve(envelope.name);
        if (handler == null) {
          await broker.deadLetter(delivery, reason: 'unregistered-task');
          return;
        }

        await _runConsumeMiddleware(delivery);

        final rateSpec = handler.options.rateLimit != null
            ? _parseRate(handler.options.rateLimit!)
            : null;
        if (rateLimiter != null && rateSpec != null) {
          final decision = await rateLimiter!.acquire(
            _rateLimitKey(handler.options, envelope),
            tokens: rateSpec.tokens,
            interval: rateSpec.period,
            meta: {'task': envelope.name},
          );
          if (!decision.allowed) {
            final backoff =
                decision.retryAfter ??
                retryStrategy.nextDelay(
                  envelope.attempt,
                  StateError('rate-limit'),
                  StackTrace.current,
                );
            await broker.nack(delivery, requeue: false);
            await broker.publish(
              envelope.copyWith(notBefore: DateTime.now().add(backoff)),
            );
            await backend.set(
              envelope.id,
              TaskState.retried,
              attempt: envelope.attempt,
              meta: {
                ...envelope.meta,
                'rateLimited': true,
                'retryAfterMs': backoff.inMilliseconds,
              },
            );
            _events.add(
              WorkerEvent(
                type: WorkerEventType.retried,
                envelope: envelope,
                data: {
                  'rateLimited': true,
                  'retryAfterMs': backoff.inMilliseconds,
                },
              ),
            );
            return;
          }
        }

        _trackDelivery(delivery);
        final groupId = envelope.headers['stem-group-id'];

        stemLogger.debug(
          'Task {task} started',
          Context(
            _logContext({
              'task': envelope.name,
              'id': envelope.id,
              'attempt': envelope.attempt,
              'queue': envelope.queue,
            }),
          ),
        );
        StemMetrics.instance.increment(
          'stem.tasks.started',
          tags: {'task': envelope.name, 'queue': envelope.queue},
        );

        await backend.set(
          envelope.id,
          TaskState.running,
          attempt: envelope.attempt,
          meta: {
            ...envelope.meta,
            'queue': envelope.queue,
            'worker': consumerName,
          },
        );

        final context = TaskContext(
          id: envelope.id,
          attempt: envelope.attempt,
          headers: envelope.headers,
          meta: envelope.meta,
          heartbeat: () => _sendHeartbeat(envelope.id),
          extendLease: (duration) async {
            await broker.extendLease(delivery, duration);
            _recordLeaseRenewal(delivery);
            _restartLeaseTimer(delivery, duration);
            _noteLeaseRenewal(delivery);
          },
          progress: (progress, {data}) async =>
              _reportProgress(envelope, progress, data: data),
        );

        Timer? heartbeatTimer;
        Timer? softTimer;
        _scheduleLeaseRenewal(delivery);

        dynamic result;

        try {
          heartbeatTimer = _startHeartbeat(envelope.id);
          softTimer = _scheduleSoftLimit(envelope, handler.options);

          result = await tracer.trace(
            'stem.execute.${envelope.name}',
            () => _invokeWithMiddleware(
              context,
              () => _executeWithHardLimit(handler, context, envelope),
            ),
            spanKind: otel.SpanKind.internal,
            attributes: spanAttributes,
          );

          _cancelLeaseTimer(delivery.receipt);
          _heartbeatTimers.remove(envelope.id)?.cancel();

          final successMeta = {
            ...envelope.meta,
            'queue': envelope.queue,
            'worker': consumerName,
            'completedAt': DateTime.now().toIso8601String(),
          };
          final successStatus = TaskStatus(
            id: envelope.id,
            state: TaskState.succeeded,
            payload: result,
            error: null,
            attempt: envelope.attempt,
            meta: successMeta,
          );
          await broker.ack(delivery);
          await backend.set(
            envelope.id,
            TaskState.succeeded,
            payload: result,
            attempt: envelope.attempt,
            meta: successMeta,
          );
          if (groupId != null) {
            await backend.addGroupResult(groupId, successStatus);
          }
          StemMetrics.instance.increment(
            'stem.tasks.succeeded',
            tags: {'task': envelope.name, 'queue': envelope.queue},
          );
          stemLogger.debug(
            'Task {task} succeeded',
            Context(
              _logContext({
                'task': envelope.name,
                'id': envelope.id,
                'attempt': envelope.attempt,
                'queue': envelope.queue,
                'worker': consumerName ?? 'unknown',
              }),
            ),
          );
          _events.add(
            WorkerEvent(type: WorkerEventType.completed, envelope: envelope),
          );
        } catch (error, stack) {
          await _notifyErrorMiddleware(context, error, stack);
          _cancelLeaseTimer(delivery.receipt);
          _heartbeatTimers.remove(envelope.id)?.cancel();
          await _handleFailure(
            handler,
            delivery,
            envelope,
            error,
            stack,
            groupId,
          );
        } finally {
          heartbeatTimer?.cancel();
          softTimer?.cancel();
          final completed = _releaseDelivery(envelope);
          if (completed != null) {
            final duration = DateTime.now().toUtc().difference(
              completed.startedAt,
            );
            StemMetrics.instance.recordDuration(
              'stem.task.duration',
              duration,
              tags: {'task': envelope.name, 'queue': envelope.queue},
            );
          }
        }
      },
      context: parentContext,
      spanKind: otel.SpanKind.consumer,
      attributes: spanAttributes,
    );
  }

  Future<void> _runConsumeMiddleware(Delivery delivery) async {
    Future<void> run(int index) async {
      if (index >= middleware.length) return;
      await middleware[index].onConsume(delivery, () => run(index + 1));
    }

    await run(0);
  }

  Future<void> _notifyErrorMiddleware(
    TaskContext context,
    Object error,
    StackTrace stack,
  ) async {
    for (final m in middleware) {
      await m.onError(context, error, stack);
    }
  }

  Future<dynamic> _invokeWithMiddleware(
    TaskContext context,
    Future<dynamic> Function() handler,
  ) async {
    dynamic result;

    Future<void> run(int index) async {
      if (index >= middleware.length) {
        result = await handler();
        return;
      }
      await middleware[index].onExecute(context, () => run(index + 1));
    }

    await run(0);
    return result;
  }

  Future<dynamic> _executeWithHardLimit(
    TaskHandler handler,
    TaskContext context,
    Envelope envelope,
  ) {
    final hard = handler.options.hardTimeLimit;
    if (_shouldUseIsolate(handler)) {
      return _runInIsolate(handler, context, envelope, hardTimeout: hard);
    }

    final future = handler.call(context, envelope.args);
    if (hard == null) {
      return future;
    }
    return future.timeout(
      hard,
      onTimeout: () => throw TimeoutException(
        'hard time limit exceeded for ${handler.name}',
      ),
    );
  }

  Timer? _scheduleSoftLimit(Envelope envelope, TaskOptions options) {
    final soft = options.softTimeLimit;
    if (soft == null) return null;
    return Timer(soft, () {
      _events.add(
        WorkerEvent(
          type: WorkerEventType.timeout,
          envelope: envelope,
          data: {'level': 'soft'},
        ),
      );
    });
  }

  Timer? _startHeartbeat(String envelopeId) {
    if (heartbeatInterval <= Duration.zero) return null;
    final timer = Timer.periodic(
      heartbeatInterval,
      (_) => _sendHeartbeat(envelopeId),
    );
    _heartbeatTimers[envelopeId]?.cancel();
    _heartbeatTimers[envelopeId] = timer;
    return timer;
  }

  void _scheduleLeaseRenewal(Delivery delivery) {
    final expiresAt = delivery.leaseExpiresAt;
    if (expiresAt == null) return;
    final remainingMs = expiresAt.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0) return;
    final interval = Duration(
      milliseconds: (remainingMs ~/ 2).clamp(1000, 30000),
    );
    _startLeaseTimer(delivery, interval);
    _noteLeaseRenewal(delivery);
  }

  void _restartLeaseTimer(Delivery delivery, Duration duration) {
    final intervalMs = (duration.inMilliseconds ~/ 2).clamp(1000, 30000);
    _startLeaseTimer(delivery, Duration(milliseconds: intervalMs));
    _noteLeaseRenewal(delivery);
  }

  void _startLeaseTimer(Delivery delivery, Duration interval) {
    _leaseTimers[delivery.receipt]?.cancel();
    final timer = Timer.periodic(interval, (_) async {
      await broker.extendLease(delivery, interval);
      _recordLeaseRenewal(delivery);
      _noteLeaseRenewal(delivery);
    });
    _leaseTimers[delivery.receipt] = timer;
  }

  void _cancelLeaseTimer(String receipt) {
    _leaseTimers.remove(receipt)?.cancel();
  }

  void _noteLeaseRenewal(Delivery delivery) {
    final now = DateTime.now().toUtc();
    _lastLeaseRenewal = now;
    final active = _activeDeliveries[delivery.envelope.id];
    if (active != null) {
      active.lastLeaseRenewal = now;
    }
  }

  Future<void> _handleFailure(
    TaskHandler handler,
    Delivery delivery,
    Envelope envelope,
    Object error,
    StackTrace stack,
    String? groupId,
  ) async {
    final canRetry = envelope.attempt < handler.options.maxRetries;
    if (canRetry) {
      final delay = retryStrategy.nextDelay(envelope.attempt, error, stack);
      await broker.nack(delivery, requeue: false);
      await broker.publish(
        envelope.copyWith(
          attempt: envelope.attempt + 1,
          notBefore: DateTime.now().add(delay),
        ),
      );
      await backend.set(
        envelope.id,
        TaskState.retried,
        attempt: envelope.attempt,
        error: TaskError(
          type: error.runtimeType.toString(),
          message: error.toString(),
          stack: stack.toString(),
          retryable: true,
        ),
        meta: {...envelope.meta, 'retryDelayMs': delay.inMilliseconds},
      );
      StemMetrics.instance.increment(
        'stem.tasks.retried',
        tags: {'task': envelope.name, 'queue': envelope.queue},
      );
      _events.add(
        WorkerEvent(
          type: WorkerEventType.retried,
          envelope: envelope,
          error: error,
          stackTrace: stack,
          data: {'retryDelayMs': delay.inMilliseconds},
        ),
      );
    } else {
      final failureMeta = {
        ...envelope.meta,
        'queue': envelope.queue,
        'worker': consumerName,
        'failedAt': DateTime.now().toIso8601String(),
      };
      final failureStatus = TaskStatus(
        id: envelope.id,
        state: TaskState.failed,
        payload: null,
        error: TaskError(
          type: error.runtimeType.toString(),
          message: error.toString(),
          stack: stack.toString(),
          retryable: false,
        ),
        attempt: envelope.attempt,
        meta: failureMeta,
      );
      await broker.deadLetter(
        delivery,
        reason: 'max-retries-exhausted',
        meta: {'error': error.toString()},
      );
      await backend.set(
        envelope.id,
        TaskState.failed,
        attempt: envelope.attempt,
        error: failureStatus.error,
        meta: failureMeta,
      );
      if (groupId != null) {
        await backend.addGroupResult(groupId, failureStatus);
      }
      StemMetrics.instance.increment(
        'stem.tasks.failed',
        tags: {'task': envelope.name, 'queue': envelope.queue},
      );
      stemLogger.warning(
        'Task {task} failed: {error}',
        Context(
          _logContext({
            'task': envelope.name,
            'id': envelope.id,
            'attempt': envelope.attempt,
            'queue': envelope.queue,
            'worker': consumerName ?? 'unknown',
            'error': error.toString(),
            'stack': stack.toString(),
          }),
        ),
      );
      _events.add(
        WorkerEvent(
          type: WorkerEventType.failed,
          envelope: envelope,
          error: error,
          stackTrace: stack,
        ),
      );
    }
  }

  String _rateLimitKey(TaskOptions options, Envelope envelope) =>
      '${envelope.name}:${envelope.headers['tenant'] ?? 'global'}';

  _RateSpec? _parseRate(String rate) {
    final parts = rate.split('/');
    if (parts.length != 2) return null;
    final tokens = int.tryParse(parts[0]);
    if (tokens == null || tokens <= 0) return null;
    switch (parts[1]) {
      case 's':
        return _RateSpec(tokens: tokens, period: const Duration(seconds: 1));
      case 'm':
        return _RateSpec(tokens: tokens, period: const Duration(minutes: 1));
      case 'h':
        return _RateSpec(tokens: tokens, period: const Duration(hours: 1));
      default:
        return null;
    }
  }

  void _sendHeartbeat(String id) {
    _events.add(WorkerEvent(type: WorkerEventType.heartbeat, envelopeId: id));
  }

  void _trackDelivery(Delivery delivery) {
    final envelope = delivery.envelope;
    final id = envelope.id;
    final queueName = envelope.queue;
    final startedAt = DateTime.now().toUtc();
    _activeDeliveries[id] = _ActiveDelivery(
      queue: queueName,
      startedAt: startedAt,
    );
    _inflight += 1;
    _inflightPerQueue[queueName] = (_inflightPerQueue[queueName] ?? 0) + 1;
    _recordInflightGauge();
  }

  _ActiveDelivery? _releaseDelivery(Envelope envelope) {
    final entry = _activeDeliveries.remove(envelope.id);
    if (entry != null) {
      _inflight = math.max(0, _inflight - 1);
      final queueCount = (_inflightPerQueue[entry.queue] ?? 0) - 1;
      if (queueCount <= 0) {
        _inflightPerQueue.remove(entry.queue);
      } else {
        _inflightPerQueue[entry.queue] = queueCount;
      }
      if (_activeDeliveries.isEmpty) {
        _lastLeaseRenewal = null;
      }
      _recordInflightGauge();
    }
    return entry;
  }

  void _recordInflightGauge() {
    StemMetrics.instance.setGauge(
      'stem.worker.inflight',
      _inflight.toDouble(),
      tags: {'worker': _workerIdentifier, 'namespace': namespace},
    );
  }

  Future<void> _recordQueueDepth() async {
    try {
      final depth = await broker.pendingCount(queue);
      if (depth == null) return;
      _lastQueueDepth = depth;
      StemMetrics.instance.setGauge(
        'stem.queue.depth',
        depth.toDouble(),
        tags: {
          'queue': queue,
          'worker': _workerIdentifier,
          'namespace': namespace,
        },
      );
    } catch (_) {
      // Swallow errors to avoid impacting worker loops; rely on logging elsewhere.
    }
  }

  void _recordLeaseRenewal(Delivery delivery) {
    final envelope = delivery.envelope;
    StemMetrics.instance.increment(
      'stem.lease.renewed',
      tags: {
        'queue': envelope.queue,
        'task': envelope.name,
        'worker': _workerIdentifier,
      },
    );
  }

  Map<String, Object> _logContext(Map<String, Object> base) {
    final traceFields = StemTracer.instance.traceFields();
    if (traceFields.isEmpty) return base;
    return {...base, ...traceFields};
  }

  void _startWorkerHeartbeatLoop() {
    _workerHeartbeatTimer?.cancel();
    if (workerHeartbeatInterval <= Duration.zero) return;
    _workerHeartbeatTimer = Timer.periodic(
      workerHeartbeatInterval,
      (_) => unawaited(_publishWorkerHeartbeat()),
    );
  }

  Future<void> _publishWorkerHeartbeat() async {
    if (!_running) return;
    await _recordQueueDepth();
    final heartbeat = _buildHeartbeat();
    try {
      await heartbeatTransport.publish(heartbeat);
    } catch (error, stack) {
      stemLogger.warning(
        'Worker heartbeat publish failed: $error',
        Context({
          'worker': _workerIdentifier,
          'channel': WorkerHeartbeat.topic(namespace),
          'stack': stack.toString(),
        }),
      );
    }
    try {
      await backend.setWorkerHeartbeat(heartbeat);
    } catch (error, stack) {
      stemLogger.warning(
        'Failed to persist worker heartbeat to backend: $error',
        Context({'worker': _workerIdentifier, 'stack': stack.toString()}),
      );
    }
  }

  WorkerHeartbeat _buildHeartbeat() {
    final now = DateTime.now().toUtc();
    final isolatePool = _isolatePool;
    final activeIsolates =
        isolatePool?.activeCount ?? math.min(_inflight, concurrency);
    final queues =
        _inflightPerQueue.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => QueueHeartbeat(name: entry.key, inflight: entry.value),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return WorkerHeartbeat(
      workerId: _workerIdentifier,
      namespace: namespace,
      timestamp: now,
      isolateCount: activeIsolates,
      inflight: _inflight,
      lastLeaseRenewal: _lastLeaseRenewal,
      queues: queues,
      extras: () {
        final extras = {
          'host': Platform.localHostname,
          'pid': pid,
          'concurrency': concurrency,
          'prefetch': prefetch,
        };
        if (_lastQueueDepth != null) {
          extras['queueDepth'] = _lastQueueDepth!;
        }
        return extras;
      }(),
    );
  }

  String get _workerIdentifier =>
      consumerName != null && consumerName!.isNotEmpty
      ? consumerName!
      : 'stem-worker-$pid';

  void _reportProgress(
    Envelope envelope,
    double progress, {
    Map<String, Object?>? data,
  }) {
    _events.add(
      WorkerEvent(
        type: WorkerEventType.progress,
        envelope: envelope,
        progress: progress,
        data: data,
      ),
    );
  }

  bool _shouldUseIsolate(TaskHandler handler) =>
      handler.isolateEntrypoint != null;

  Future<Object?> _runInIsolate(
    TaskHandler handler,
    TaskContext context,
    Envelope envelope, {
    Duration? hardTimeout,
  }) async {
    final entrypoint = handler.isolateEntrypoint;
    if (entrypoint == null) {
      return handler.call(context, envelope.args);
    }

    final pool = await _ensureIsolatePool();

    final outcome = await pool.execute(
      entrypoint,
      envelope.args,
      envelope.headers,
      envelope.meta,
      envelope.attempt,
      _controlHandler(context),
      hardTimeout: hardTimeout,
      taskName: handler.name,
    );

    if (outcome is TaskExecutionSuccess) {
      return outcome.value;
    } else if (outcome is TaskExecutionFailure) {
      Error.throwWithStackTrace(outcome.error, outcome.stackTrace);
    } else if (outcome is TaskExecutionTimeout) {
      throw TimeoutException(
        'hard time limit exceeded for ${outcome.taskName}',
        outcome.limit,
      );
    }

    throw StateError('Unexpected execution outcome: $outcome');
  }

  TaskControlHandler _controlHandler(TaskContext context) {
    return (signal) async {
      if (signal is HeartbeatSignal) {
        context.heartbeat();
      } else if (signal is ExtendLeaseSignal) {
        await context.extendLease(signal.by);
      } else if (signal is ProgressSignal) {
        await context.progress(signal.percentComplete, data: signal.data);
      }
    };
  }

  Future<TaskIsolatePool> _ensureIsolatePool() {
    final existing = _isolatePool;
    if (existing != null) return Future.value(existing);
    final future = _poolFuture;
    if (future != null) return future;
    final creation = _createPool();
    _poolFuture = creation;
    return creation;
  }

  Future<TaskIsolatePool> _createPool() async {
    final pool = TaskIsolatePool(size: concurrency);
    await pool.start();
    _isolatePool = pool;
    return pool;
  }

  static int _normalizeConcurrency(int? value) =>
      math.max(1, value ?? Platform.numberOfProcessors);

  static int _calculatePrefetch(
    int? provided,
    int concurrency,
    int multiplier,
  ) => math.max(1, provided ?? concurrency * multiplier);
}

/// An event emitted during worker operation.
///
/// Provides details about task lifecycle, errors, and progress.
class WorkerEvent {
  /// Creates a worker event.
  ///
  /// [type] indicates the event kind. [envelope] provides task details for
  /// relevant events. [envelopeId] identifies the task for heartbeats.
  /// [error] and [stackTrace] capture exceptions. [progress] shows completion
  /// percentage. [data] holds additional event-specific information.
  WorkerEvent({
    required this.type,
    this.envelope,
    this.envelopeId,
    this.error,
    this.stackTrace,
    this.progress,
    this.data,
  });

  /// The type of event.
  final WorkerEventType type;

  /// The envelope associated with the event, if applicable.
  final Envelope? envelope;

  /// The envelope ID for heartbeat events.
  final String? envelopeId;

  /// The error that occurred, if any.
  final Object? error;

  /// The stack trace for the error.
  final StackTrace? stackTrace;

  /// The progress percentage, if reporting progress.
  final double? progress;

  /// Additional data for the event.
  final Map<String, Object?>? data;
}

/// Types of events a worker can emit.
enum WorkerEventType {
  /// A heartbeat signal for an active task.
  heartbeat,

  /// Progress update for a task.
  progress,

  /// Soft timeout warning for a task.
  timeout,

  /// Task completed successfully.
  completed,

  /// Task was retried after failure.
  retried,

  /// Task failed permanently.
  failed,

  /// An error occurred outside task execution.
  error,
}

/// Parsed rate limit specification.
class _RateSpec {
  /// Creates a rate spec.
  ///
  /// [tokens] is the number allowed per [period].
  const _RateSpec({required this.tokens, required this.period});

  /// The number of tokens allowed.
  final int tokens;

  /// The period over which tokens apply.
  final Duration period;
}

/// Tracks an active task delivery.
class _ActiveDelivery {
  /// Creates an active delivery record.
  ///
  /// [queue] is the queue name. [startedAt] is the start time.
  _ActiveDelivery({required this.queue, required this.startedAt});

  /// The queue this delivery belongs to.
  final String queue;

  /// When the task started.
  final DateTime startedAt;

  /// The last lease renewal time.
  DateTime? lastLeaseRenewal;
}
