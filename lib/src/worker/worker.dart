import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:contextual/contextual.dart';
import 'package:opentelemetry/api.dart' as otel;

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../core/retry.dart';
import '../control/control_messages.dart';
import '../control/revoke_store.dart';
import '../observability/logging.dart';
import '../observability/metrics.dart';
import '../observability/config.dart';
import '../observability/heartbeat.dart';
import '../observability/heartbeat_transport.dart';
import '../observability/tracing.dart';
import '../security/signing.dart';
import '../core/task_invocation.dart';
import 'isolate_pool.dart';
import 'worker_config.dart';
import '../signals/emitter.dart';
import '../signals/payloads.dart';

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
enum WorkerShutdownMode { warm, soft, hard }

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
  /// heartbeats. [observability] configures metrics and logging. The optional
  /// [signer] verifies payload signatures (see [SigningConfig]); invalid
  /// envelopes are dead-lettered with a `signature-invalid` reason.
  Worker({
    required this.broker,
    required this.registry,
    required this.backend,
    this.rateLimiter,
    this.middleware = const [],
    this.revokeStore,
    RetryStrategy? retryStrategy,
    this.queue = 'default',
    RoutingSubscription? subscription,
    this.consumerName,
    int? concurrency,
    int prefetchMultiplier = 2,
    int? prefetch,
    this.heartbeatInterval = const Duration(seconds: 10),
    Duration? workerHeartbeatInterval,
    HeartbeatTransport? heartbeatTransport,
    String heartbeatNamespace = 'stem',
    WorkerAutoscaleConfig? autoscale,
    WorkerLifecycleConfig? lifecycle,
    ObservabilityConfig? observability,
    this.signer,
  }) : workerHeartbeatInterval =
           observability?.heartbeatInterval ??
           workerHeartbeatInterval ??
           heartbeatInterval,
       heartbeatTransport =
           heartbeatTransport ?? const NoopHeartbeatTransport(),
       namespace = observability?.namespace ?? heartbeatNamespace,
       concurrency = _normalizeConcurrency(concurrency),
       autoscaleConfig = _resolveAutoscaleConfig(
         autoscale,
         _normalizeConcurrency(concurrency),
       ),
       lifecycleConfig = lifecycle ?? const WorkerLifecycleConfig(),
       prefetchMultiplier = math.max(1, prefetchMultiplier),
       prefetch = _calculatePrefetch(
         prefetch,
         _normalizeConcurrency(concurrency),
         math.max(1, prefetchMultiplier),
       ),
       retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy() {
    observability?.applyMetricExporters();
    observability?.applySignalConfiguration();
    _maxConcurrency = this.concurrency;
    final autoscaleMax =
        autoscaleConfig.maxConcurrency != null &&
            autoscaleConfig.maxConcurrency! > 0
        ? math.min(autoscaleConfig.maxConcurrency!, _maxConcurrency)
        : _maxConcurrency;
    if (autoscaleConfig.enabled) {
      _currentConcurrency = math.min(autoscaleMax, _maxConcurrency);
      if (_currentConcurrency < autoscaleConfig.minConcurrency) {
        _currentConcurrency = autoscaleConfig.minConcurrency;
      }
    } else {
      _currentConcurrency = _maxConcurrency;
    }
    _currentConcurrency = math.max(1, _currentConcurrency);
    _recordConcurrencyGauge();

    final resolvedSubscription =
        subscription ?? RoutingSubscription.singleQueue(queue);

    List<String> normalize(List<String> values) {
      final seen = <String>{};
      final result = <String>[];
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) continue;
        if (seen.add(trimmed)) {
          result.add(trimmed);
        }
      }
      return result;
    }

    final normalizedQueues = normalize(
      resolvedSubscription.resolveQueues(queue),
    );
    if (normalizedQueues.isEmpty) {
      normalizedQueues.add(queue);
    }
    final normalizedBroadcasts = normalize(
      resolvedSubscription.broadcastChannels,
    );

    this.subscription = resolvedSubscription;
    subscriptionQueues = List.unmodifiable(normalizedQueues);
    subscriptionBroadcasts = List.unmodifiable(normalizedBroadcasts);
    _signals = StemSignalEmitter(defaultSender: _workerIdentifier);
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
  final WorkerAutoscaleConfig autoscaleConfig;
  final WorkerLifecycleConfig lifecycleConfig;
  final Duration heartbeatInterval;
  final Duration workerHeartbeatInterval;
  final HeartbeatTransport heartbeatTransport;
  final String namespace;
  final PayloadSigner? signer;
  final RevokeStore? revokeStore;

  late final RoutingSubscription subscription;
  late final List<String> subscriptionQueues;
  late final List<String> subscriptionBroadcasts;
  late final StemSignalEmitter _signals;

  List<String> get _effectiveQueues =>
      subscriptionQueues.isNotEmpty ? subscriptionQueues : [queue];

  List<String> get _broadcastSubscriptions => subscriptionBroadcasts;

  String get primaryQueue =>
      _effectiveQueues.isNotEmpty ? _effectiveQueues.first : queue;

  final Map<String, Timer> _leaseTimers = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, StreamSubscription<Delivery>> _subscriptions = {};
  final StreamController<WorkerEvent> _events = StreamController.broadcast();
  TaskIsolatePool? _isolatePool;
  Future<TaskIsolatePool>? _poolFuture;
  late final int _maxConcurrency;
  late int _currentConcurrency;
  Timer? _autoscaleTimer;
  bool _autoscaleEvaluating = false;
  DateTime? _lastScaleUp;
  DateTime? _lastScaleDown;
  DateTime? _idleSince;
  Completer<void>? _shutdownCompleter;
  WorkerShutdownMode? _shutdownMode;
  Completer<void>? _drainCompleter;
  StreamSubscription<ProcessSignal>? _sigintSub;
  StreamSubscription<ProcessSignal>? _sigtermSub;
  StreamSubscription<ProcessSignal>? _sigquitSub;

  bool _running = false;
  final Map<String, _ActiveDelivery> _activeDeliveries = {};
  final Map<String, int> _inflightPerQueue = {};
  int _inflight = 0;
  Timer? _workerHeartbeatTimer;
  DateTime? _lastLeaseRenewal;
  int? _lastQueueDepth;
  final Map<String, RevokeEntry> _revocations = {};
  int _latestRevocationVersion = 0;

  /// A stream of events emitted during task processing.
  ///
  /// Includes events like task start, completion, failure, and heartbeats.
  Stream<WorkerEvent> get events => _events.stream;

  /// Current active concurrency for isolate-backed tasks.
  int get activeConcurrency => _currentConcurrency;

  /// Starts the worker, beginning task consumption and processing.
  ///
  /// Initializes heartbeat loops and subscribes to the queue. Throws if already
  /// running.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _shutdownMode = null;
    _shutdownCompleter = null;
    _idleSince = null;
    _lastScaleUp = null;
    _lastScaleDown = null;
    _drainCompleter = null;
    await _signals.workerInit(_workerInfoSnapshot);
    await _initializeRevocations();
    _startWorkerHeartbeatLoop();
    _recordInflightGauge();
    _recordConcurrencyGauge();
    unawaited(_publishWorkerHeartbeat());
    final queueNames = _effectiveQueues;
    if (queueNames.isEmpty) {
      throw StateError('Worker subscription resolved no queues.');
    }
    for (var index = 0; index < queueNames.length; index += 1) {
      final queueName = queueNames[index];
      final stream = broker.consume(
        RoutingSubscription(
          queues: [queueName],
          broadcastChannels: index == 0
              ? _broadcastSubscriptions
              : const <String>[],
        ),
        prefetch: prefetch,
        consumerName: consumerName,
      );
      final subscription = stream.listen(
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
      _subscriptions[queueName] = subscription;
    }
    _startControlPlane();
    _startAutoscaler();
    _installSignalHandlers();
    await _signals.workerReady(_workerInfoSnapshot);
  }

  /// Stops the worker according to [mode], cancelling subscriptions and resources.
  ///
  /// Warm shutdown drains in-flight tasks before exiting. Soft shutdown requests
  /// cooperative termination and escalates to hard shutdown if tasks ignore the
  /// grace period. Hard shutdown immediately requeues in-flight deliveries.
  Future<void> shutdown({
    WorkerShutdownMode mode = WorkerShutdownMode.hard,
  }) async {
    if (_shutdownCompleter != null) {
      if (mode == WorkerShutdownMode.hard &&
          (_shutdownMode ?? WorkerShutdownMode.warm) !=
              WorkerShutdownMode.hard) {
        _shutdownMode = WorkerShutdownMode.hard;
        await _forceStopActiveTasks();
      }
      return _shutdownCompleter!.future;
    }

    _shutdownMode = mode;
    final completer = Completer<void>();
    _shutdownCompleter = completer;
    _running = false;

    await _signals.workerStopping(_workerInfoSnapshot, reason: mode.name);

    _autoscaleTimer?.cancel();
    _autoscaleTimer = null;
    _workerHeartbeatTimer?.cancel();
    _workerHeartbeatTimer = null;

    await _cancelAllSubscriptions();
    await _stopSignalWatchers();

    bool drained = false;
    if (mode == WorkerShutdownMode.hard) {
      await _forceStopActiveTasks();
    } else {
      if (mode == WorkerShutdownMode.soft) {
        _requestTerminationForActiveTasks(reason: mode.name);
      }
      drained = await _awaitDrainWithTimeout(
        mode == WorkerShutdownMode.soft
            ? lifecycleConfig.softGracePeriod
            : null,
      );
      if (!drained) {
        await _forceStopActiveTasks();
      }
    }

    await _disposePool();
    _cancelTimers();
    await heartbeatTransport.close();
    _revocations.clear();
    _latestRevocationVersion = 0;
    _inflightPerQueue.clear();
    _inflight = 0;
    _idleSince = null;
    _recordConcurrencyGauge();

    if (!_events.isClosed) {
      await _events.close();
    }

    await _signals.workerShutdown(_workerInfoSnapshot, reason: mode.name);

    completer.complete();
    return completer.future;
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

        final groupId = envelope.headers['stem-group-id'];

        if (_isTaskRevoked(envelope.id)) {
          await _handleRevokedDelivery(delivery, envelope, groupId: groupId);
          return;
        }

        if (signer != null) {
          try {
            await signer!.verify(envelope);
          } on SignatureVerificationException catch (error, stack) {
            await _handleSignatureFailure(
              delivery,
              envelope,
              error,
              stack,
              groupId,
            );
            return;
          }
        }

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

        await _signals.taskReceived(envelope, _workerInfoSnapshot);

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

        void checkTermination() => _enforceTerminationIfRequested(envelope.id);

        final context = TaskContext(
          id: envelope.id,
          attempt: envelope.attempt,
          headers: envelope.headers,
          meta: envelope.meta,
          heartbeat: () {
            checkTermination();
            _sendHeartbeat(envelope.id);
          },
          extendLease: (duration) async {
            checkTermination();
            await broker.extendLease(delivery, duration);
            _recordLeaseRenewal(delivery);
            _restartLeaseTimer(delivery, duration);
            _noteLeaseRenewal(delivery);
          },
          progress: (progress, {data}) async {
            checkTermination();
            _reportProgress(envelope, progress, data: data);
          },
        );

        await _signals.taskPrerun(envelope, _workerInfoSnapshot, context);

        Timer? heartbeatTimer;
        Timer? softTimer;
        _scheduleLeaseRenewal(delivery);

        dynamic result;
        TaskState completionState = TaskState.running;

        try {
          checkTermination();
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
          await _signals.taskSucceeded(
            envelope,
            _workerInfoSnapshot,
            result: result,
          );
          completionState = TaskState.succeeded;
        } on TaskRevokedException catch (_) {
          _cancelLeaseTimer(delivery.receipt);
          _heartbeatTimers.remove(envelope.id)?.cancel();
          await _handleRevokedDelivery(delivery, envelope, groupId: groupId);
          completionState = TaskState.cancelled;
        } catch (error, stack) {
          await _notifyErrorMiddleware(context, error, stack);
          _cancelLeaseTimer(delivery.receipt);
          _heartbeatTimers.remove(envelope.id)?.cancel();
          completionState = await _handleFailure(
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
          await _signals.taskPostrun(
            envelope,
            _workerInfoSnapshot,
            context,
            result: result,
            state: completionState,
          );
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

  Future<void> _handleSignatureFailure(
    Delivery delivery,
    Envelope envelope,
    SignatureVerificationException error,
    StackTrace stack,
    String? groupId,
  ) async {
    await broker.deadLetter(
      delivery,
      reason: 'signature-invalid',
      meta: {
        'error': error.message,
        if (error.keyId != null) 'keyId': error.keyId!,
      },
    );

    final failureMeta = {
      ...envelope.meta,
      'queue': envelope.queue,
      'worker': consumerName,
      'failedAt': DateTime.now().toIso8601String(),
      'security': 'signature-invalid',
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
        meta: {
          'reason': error.message,
          if (error.keyId != null) 'keyId': error.keyId!,
        },
      ),
      attempt: envelope.attempt,
      meta: failureMeta,
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
      'stem.tasks.signature_invalid',
      tags: {'task': envelope.name, 'queue': envelope.queue},
    );
    StemMetrics.instance.increment(
      'stem.tasks.failed',
      tags: {'task': envelope.name, 'queue': envelope.queue},
    );

    stemLogger.error(
      'Task {task} signature verification failed',
      Context(
        _logContext({
          'task': envelope.name,
          'id': envelope.id,
          'queue': envelope.queue,
          'worker': consumerName ?? 'unknown',
          'error': error.message,
          if (error.keyId != null) 'keyId': error.keyId!,
        }),
      ),
    );

    _events.add(
      WorkerEvent(
        type: WorkerEventType.failed,
        envelope: envelope,
        error: error,
        stackTrace: stack,
        data: {'security': 'signature-invalid'},
      ),
    );
    await _signals.taskFailed(
      envelope,
      _workerInfoSnapshot,
      error: error,
      stackTrace: stack,
    );
  }

  Future<TaskState> _handleFailure(
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
      final nextRunAt = DateTime.now().add(delay);
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
      await _signals.taskRetry(
        envelope,
        _workerInfoSnapshot,
        reason: error,
        nextRetryAt: nextRunAt,
      );
      return TaskState.retried;
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
      await _signals.taskFailed(
        envelope,
        _workerInfoSnapshot,
        error: error,
        stackTrace: stack,
      );
      return TaskState.failed;
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
      envelope: envelope,
      delivery: delivery,
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
        final drain = _drainCompleter;
        if (drain != null && !drain.isCompleted) {
          drain.complete();
        }
        _drainCompleter = null;
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

  void _recordConcurrencyGauge() {
    StemMetrics.instance.setGauge(
      'stem.worker.concurrency',
      _currentConcurrency.toDouble(),
      tags: {'worker': _workerIdentifier, 'namespace': namespace},
    );
  }

  Future<void> _recordQueueDepth() async {
    try {
      final depths = await _collectQueueDepths();
      if (depths.isEmpty) return;
      _lastQueueDepth = depths.values.fold<int>(
        0,
        (previous, value) => previous + value,
      );
      for (final entry in depths.entries) {
        StemMetrics.instance.setGauge(
          'stem.queue.depth',
          entry.value.toDouble(),
          tags: {
            'queue': entry.key,
            'worker': _workerIdentifier,
            'namespace': namespace,
          },
        );
      }
    } catch (_) {
      // Swallow errors to avoid impacting worker loops; rely on logging elsewhere.
    }
  }

  Future<Map<String, int>> _collectQueueDepths() async {
    final result = <String, int>{};
    for (final queueName in _effectiveQueues) {
      final depth = await broker.pendingCount(queueName);
      if (depth != null) {
        result[queueName] = depth;
      }
    }
    return result;
  }

  Future<void> _cancelAllSubscriptions() async {
    if (_subscriptions.isEmpty) return;
    final subs = List<StreamSubscription<Delivery>>.from(_subscriptions.values);
    _subscriptions.clear();
    for (final sub in subs) {
      try {
        await sub.cancel();
      } catch (error, stack) {
        stemLogger.warning(
          'Failed to cancel subscription: $error',
          Context(_logContext({'stack': stack.toString()})),
        );
      }
    }
  }

  void _cancelTimers() {
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
  }

  Future<void> _disposePool() async {
    final pool = _isolatePool;
    _isolatePool = null;
    _poolFuture = null;
    if (pool != null) {
      await pool.dispose();
    }
  }

  Future<void> _forceStopActiveTasks() async {
    final deliveries = List<_ActiveDelivery>.from(_activeDeliveries.values);
    if (deliveries.isEmpty) return;
    for (final active in deliveries) {
      _cancelLeaseTimer(active.delivery.receipt);
      _heartbeatTimers.remove(active.envelope.id)?.cancel();
      _releaseDelivery(active.envelope);
      try {
        await broker.nack(active.delivery, requeue: true);
      } catch (error, stack) {
        stemLogger.warning(
          'Failed to requeue delivery during shutdown: $error',
          Context(
            _logContext({
              'queue': active.queue,
              'task': active.envelope.name,
              'stack': stack.toString(),
            }),
          ),
        );
      }
      _revocations.remove(active.envelope.id);
    }
  }

  void _requestTerminationForActiveTasks({required String reason}) {
    if (_activeDeliveries.isEmpty) return;
    final now = DateTime.now().toUtc();
    var version = generateRevokeVersion();
    for (final active in _activeDeliveries.values) {
      final entry = RevokeEntry(
        namespace: namespace,
        taskId: active.envelope.id,
        version: version++,
        issuedAt: now,
        terminate: true,
        reason: reason,
        requestedBy: _workerIdentifier,
      );
      _applyRevocationEntry(entry, clock: now);
    }
  }

  Future<bool> _awaitDrainWithTimeout(Duration? timeout) async {
    if (_activeDeliveries.isEmpty) return true;
    final completer = _drainCompleter ??= Completer<void>();
    if (_activeDeliveries.isEmpty && !completer.isCompleted) {
      completer.complete();
    }
    if (timeout == null) {
      await completer.future;
      _drainCompleter = null;
      return true;
    }
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      if (_drainCompleter != null && _drainCompleter!.isCompleted) {
        _drainCompleter = null;
      }
    }
  }

  Future<void> _stopSignalWatchers() async {
    final futures = <Future<void>>[];
    if (_sigintSub != null) {
      futures.add(_sigintSub!.cancel());
      _sigintSub = null;
    }
    if (_sigtermSub != null) {
      futures.add(_sigtermSub!.cancel());
      _sigtermSub = null;
    }
    if (_sigquitSub != null) {
      futures.add(_sigquitSub!.cancel());
      _sigquitSub = null;
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
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

  bool get _autoscaleEnabled => autoscaleConfig.enabled;

  void _startAutoscaler() {
    _autoscaleTimer?.cancel();
    if (!_autoscaleEnabled) return;
    _autoscaleTimer = Timer.periodic(
      autoscaleConfig.tick,
      (_) => unawaited(_evaluateAutoscale()),
    );
  }

  Future<void> _evaluateAutoscale() async {
    if (!_running || !_autoscaleEnabled) return;
    if (_autoscaleEvaluating) return;
    _autoscaleEvaluating = true;
    try {
      final depthMap = await _collectQueueDepths();
      final depth = depthMap.isEmpty
          ? _lastQueueDepth ?? 0
          : depthMap.values.fold<int>(0, (value, element) => value + element);
      if (depthMap.isNotEmpty) {
        _lastQueueDepth = depth;
      }
      final inflight = _inflight;
      final now = DateTime.now();
      final configuredMax = autoscaleConfig.maxConcurrency ?? _maxConcurrency;
      final maxAllowed = configuredMax < _maxConcurrency
          ? configuredMax
          : _maxConcurrency;
      final minAllowed = autoscaleConfig.minConcurrency <= maxAllowed
          ? autoscaleConfig.minConcurrency
          : maxAllowed;

      if (depth == 0 && inflight == 0) {
        _idleSince ??= now;
      } else {
        _idleSince = null;
      }

      final current = _currentConcurrency;
      if (depth > 0 &&
          current < maxAllowed &&
          _cooldownElapsed(
            _lastScaleUp,
            autoscaleConfig.scaleUpCooldown,
            now,
          )) {
        final backlogPerIsolate = depth / math.max(1, current);
        if (backlogPerIsolate >= autoscaleConfig.backlogPerIsolate) {
          final step = math.max(1, autoscaleConfig.scaleUpStep);
          final candidate = current + step;
          final desired = candidate > maxAllowed ? maxAllowed : candidate;
          if (desired != current) {
            await _updateConcurrency(
              desired,
              reason: 'scale-up',
              backlog: depth,
              inflight: inflight,
            );
            _lastScaleUp = now;
            _idleSince = null;
          }
        }
      }

      final idleSince = _idleSince;
      if (idleSince != null &&
          current > minAllowed &&
          now.difference(idleSince) >= autoscaleConfig.idlePeriod &&
          _cooldownElapsed(
            _lastScaleDown,
            autoscaleConfig.scaleDownCooldown,
            now,
          )) {
        final step = math.max(1, autoscaleConfig.scaleDownStep);
        final candidate = current - step;
        final desired = candidate < minAllowed ? minAllowed : candidate;
        if (desired != current) {
          await _updateConcurrency(
            desired,
            reason: 'scale-down',
            backlog: depth,
            inflight: inflight,
          );
          _lastScaleDown = now;
        }
      }
    } catch (error, stack) {
      stemLogger.warning(
        'Autoscale evaluation failed: $error',
        Context(_logContext({'stack': stack.toString()})),
      );
    } finally {
      _autoscaleEvaluating = false;
    }
  }

  Future<void> _updateConcurrency(
    int newConcurrency, {
    required String reason,
    required int backlog,
    required int inflight,
  }) async {
    final clamped = math.max(1, math.min(newConcurrency, _maxConcurrency));
    if (clamped == _currentConcurrency) return;
    final previous = _currentConcurrency;
    _currentConcurrency = clamped;
    if (_currentConcurrency > previous) {
      _idleSince = null;
    }

    final pool = _isolatePool;
    if (pool != null) {
      await pool.resize(_currentConcurrency);
    }

    _recordConcurrencyGauge();

    stemLogger.info(
      'Adjusted concurrency from {from} to {to} ({reason})',
      Context(
        _logContext({
          'from': previous,
          'to': _currentConcurrency,
          'reason': reason,
          'backlog': backlog,
          'inflight': inflight,
        }),
      ),
    );
  }

  bool _cooldownElapsed(DateTime? last, Duration cooldown, DateTime clock) {
    if (cooldown <= Duration.zero) return true;
    if (last == null) return true;
    return clock.difference(last) >= cooldown;
  }

  void _handleIsolateRecycle(IsolateRecycleEvent event) {
    final ctx = Context(
      _logContext({
        'reason': event.reason.name,
        'tasks': event.tasksExecuted,
        if (event.memoryBytes != null) 'memoryBytes': event.memoryBytes!,
      }),
    );
    switch (event.reason) {
      case IsolateRecycleReason.maxTasks:
        stemLogger.info('Recycled isolate after max task threshold', ctx);
        break;
      case IsolateRecycleReason.memory:
        stemLogger.info('Recycled isolate after memory threshold', ctx);
        break;
      case IsolateRecycleReason.scaleDown:
      case IsolateRecycleReason.shutdown:
        stemLogger.debug('Recycled isolate ({reason})', ctx);
        break;
    }
  }

  void _installSignalHandlers() {
    if (!lifecycleConfig.installSignalHandlers) return;
    _sigtermSub ??= _safeWatch(ProcessSignal.sigterm, () {
      if (_running) {
        unawaited(shutdown(mode: WorkerShutdownMode.warm));
      }
    });
    _sigintSub ??= _safeWatch(ProcessSignal.sigint, () {
      if (_running) {
        unawaited(shutdown(mode: WorkerShutdownMode.soft));
      }
    });
    _sigquitSub ??= _safeWatch(ProcessSignal.sigquit, () {
      if (_running) {
        unawaited(shutdown(mode: WorkerShutdownMode.hard));
      }
    });
  }

  StreamSubscription<ProcessSignal>? _safeWatch(
    ProcessSignal signal,
    void Function() handler,
  ) {
    try {
      return signal.watch().listen((_) => handler());
    } on SignalException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  WorkerShutdownMode _parseShutdownMode(String? value) {
    switch (value?.toLowerCase()) {
      case 'force':
      case 'hard':
        return WorkerShutdownMode.hard;
      case 'soft':
        return WorkerShutdownMode.soft;
      case 'warm':
      case 'graceful':
      default:
        return WorkerShutdownMode.warm;
    }
  }

  Future<Map<String, Object?>> _handleShutdownRequest(
    WorkerShutdownMode mode,
  ) async {
    if (_shutdownCompleter != null) {
      return {
        'status': 'in-progress',
        'mode': (_shutdownMode ?? WorkerShutdownMode.warm).name,
        'active': _activeDeliveries.length,
      };
    }
    unawaited(shutdown(mode: mode));
    return {
      'status': 'initiated',
      'mode': mode.name,
      'active': _activeDeliveries.length,
    };
  }

  Future<void> _publishWorkerHeartbeat() async {
    if (!_running) return;
    await _recordQueueDepth();
    final heartbeat = _buildHeartbeat();
    await _signals.workerHeartbeat(_workerInfoSnapshot, heartbeat.timestamp);
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
        isolatePool?.activeCount ?? math.min(_inflight, _currentConcurrency);
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
          'concurrency': _currentConcurrency,
          'maxConcurrency': concurrency,
          'prefetch': prefetch,
          'autoscale': autoscaleConfig.enabled,
        };
        if (_lastQueueDepth != null) {
          extras['queueDepth'] = _lastQueueDepth!;
        }
        extras['subscriptions'] = {
          'queues': subscriptionQueues,
          if (subscriptionBroadcasts.isNotEmpty)
            'broadcasts': subscriptionBroadcasts,
        };
        return extras;
      }(),
    );
  }

  String get _workerIdentifier =>
      consumerName != null && consumerName!.isNotEmpty
      ? consumerName!
      : 'stem-worker-$pid';

  WorkerInfo get _workerInfoSnapshot => WorkerInfo(
    id: _workerIdentifier,
    queues: subscriptionQueues,
    broadcasts: subscriptionBroadcasts,
  );

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

  Future<void> _initializeRevocations() async {
    if (revokeStore == null) return;
    try {
      await _syncRevocations();
    } catch (error, stack) {
      stemLogger.warning(
        'Failed to initialize revoke cache: $error',
        Context(_logContext({'stack': stack.toString()})),
      );
    }
  }

  Future<void> _syncRevocations() async {
    final store = revokeStore;
    if (store == null) return;
    final now = DateTime.now().toUtc();
    try {
      final fetched = await store.list(namespace);
      for (final entry in fetched) {
        _applyRevocationEntry(entry, clock: now);
      }
      await store.pruneExpired(namespace, now);
      _pruneExpiredLocalRevocations(now);
    } catch (error, stack) {
      stemLogger.warning(
        'Failed to synchronize revokes: $error',
        Context(_logContext({'stack': stack.toString()})),
      );
    }
  }

  void _pruneExpiredLocalRevocations(DateTime now) {
    final remove = <String>[];
    _revocations.forEach((key, value) {
      if (value.isExpired(now)) {
        remove.add(key);
      }
    });
    for (final key in remove) {
      _revocations.remove(key);
    }
  }

  RevokeEntry? _revocationFor(String taskId) {
    final entry = _revocations[taskId];
    if (entry == null) return null;
    if (entry.isExpired(DateTime.now().toUtc())) {
      _revocations.remove(taskId);
      return null;
    }
    return entry;
  }

  void _enforceTerminationIfRequested(String taskId) {
    final entry = _revocationFor(taskId);
    if (entry != null && entry.terminate) {
      throw TaskRevokedException(
        taskId: taskId,
        reason: entry.reason,
        requestedBy: entry.requestedBy,
      );
    }
  }

  void _applyRevocationEntry(RevokeEntry entry, {DateTime? clock}) {
    final now = clock ?? DateTime.now().toUtc();
    if (entry.isExpired(now)) {
      _revocations.remove(entry.taskId);
      return;
    }
    final current = _revocations[entry.taskId];
    if (current == null || entry.version >= current.version) {
      _revocations[entry.taskId] = entry;
      if (entry.version > _latestRevocationVersion) {
        _latestRevocationVersion = entry.version;
      }
    }
  }

  bool _isTaskRevoked(String taskId) {
    return _revocationFor(taskId) != null;
  }

  Future<void> _handleRevokedDelivery(
    Delivery delivery,
    Envelope envelope, {
    String? groupId,
  }) async {
    final revokeEntry = _revocationFor(envelope.id);
    await broker.ack(delivery);
    final meta = {
      ...envelope.meta,
      'queue': envelope.queue,
      'worker': consumerName,
      'revoked': true,
    };
    if (revokeEntry?.reason != null) {
      meta['revokedReason'] = revokeEntry!.reason;
    }
    if (revokeEntry?.requestedBy != null) {
      meta['revokedBy'] = revokeEntry!.requestedBy;
    }
    if (revokeEntry != null) {
      meta['revokedAt'] = revokeEntry.issuedAt.toIso8601String();
    }
    final status = TaskStatus(
      id: envelope.id,
      state: TaskState.cancelled,
      payload: null,
      error: null,
      attempt: envelope.attempt,
      meta: meta,
    );
    await backend.set(
      envelope.id,
      TaskState.cancelled,
      attempt: envelope.attempt,
      meta: meta,
    );
    if (groupId != null) {
      await backend.addGroupResult(groupId, status);
    }
    StemMetrics.instance.increment(
      'stem.tasks.revoked',
      tags: {'task': envelope.name, 'queue': envelope.queue},
    );
    stemLogger.info(
      'Task {task} revoked',
      Context(
        _logContext({
          'task': envelope.name,
          'id': envelope.id,
          'queue': envelope.queue,
          'worker': consumerName ?? 'unknown',
        }),
      ),
    );
    _events.add(
      WorkerEvent(
        type: WorkerEventType.revoked,
        envelope: envelope,
        data: {
          'reason': revokeEntry?.reason,
          'requestedBy': revokeEntry?.requestedBy,
        },
      ),
    );
    await _signals.taskRevoked(
      envelope,
      _workerInfoSnapshot,
      reason: revokeEntry?.reason ?? 'revoked',
    );
    _revocations.remove(envelope.id);
  }

  Future<Map<String, Object?>> _processRevokeCommand(
    ControlCommandMessage command,
  ) async {
    final payload = command.payload;
    final namespaceOverride = (payload['namespace'] as String?)?.trim();
    final defaultNamespace =
        namespaceOverride != null && namespaceOverride.isNotEmpty
        ? namespaceOverride
        : namespace;
    final rawRevocations = (payload['revocations'] as List?) ?? const [];
    final requester = (payload['requester'] as String?)?.trim();
    final now = DateTime.now().toUtc();

    final entries = <RevokeEntry>[];
    for (final raw in rawRevocations) {
      if (raw is! Map) continue;
      final map = raw.cast<String, Object?>();
      final taskId = (map['taskId'] as String?)?.trim();
      if (taskId == null || taskId.isEmpty) continue;
      final targetNamespace = (map['namespace'] as String?)?.trim();
      final entryNamespace =
          targetNamespace != null && targetNamespace.isNotEmpty
          ? targetNamespace
          : defaultNamespace;
      if (entryNamespace != namespace) {
        continue;
      }
      final issuedAtStr = (map['issuedAt'] as String?)?.trim();
      DateTime issuedAt;
      if (issuedAtStr != null && issuedAtStr.isNotEmpty) {
        issuedAt = DateTime.parse(issuedAtStr).toUtc();
      } else {
        issuedAt = now;
      }
      final expiresAtStr = (map['expiresAt'] as String?)?.trim();
      final expiresAt = expiresAtStr != null && expiresAtStr.isNotEmpty
          ? DateTime.parse(expiresAtStr).toUtc()
          : null;
      final versionValue = map['version'];
      final version = versionValue is num
          ? versionValue.toInt()
          : generateRevokeVersion();
      final terminate = map['terminate'] == true;
      final reason = (map['reason'] as String?)?.trim();
      final requestedBy = (map['requestedBy'] as String?)?.trim() ?? requester;

      entries.add(
        RevokeEntry(
          namespace: entryNamespace,
          taskId: taskId,
          version: version,
          issuedAt: issuedAt,
          terminate: terminate,
          reason: reason,
          requestedBy: requestedBy,
          expiresAt: expiresAt,
        ),
      );
    }

    final result = await _applyRevocationEntries(entries);
    result['latestVersion'] = _latestRevocationVersion;
    result['namespace'] = namespace;
    return result;
  }

  Future<Map<String, Object?>> _applyRevocationEntries(
    List<RevokeEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return {
        'tasks': const <String>[],
        'revoked': 0,
        'inflight': const <String>[],
      };
    }

    final now = DateTime.now().toUtc();
    final applied = <String>[];
    final inflight = <String>[];
    final ignored = <String>[];
    final expired = <String>[];

    final store = revokeStore;
    if (store != null) {
      try {
        await store.upsertAll(entries);
        await store.pruneExpired(namespace, now);
      } catch (error, stack) {
        stemLogger.warning(
          'Failed to persist revocations: $error',
          Context(_logContext({'stack': stack.toString()})),
        );
        throw StateError('Failed to persist revocations: $error');
      }
    }

    for (final entry in entries) {
      if (entry.namespace != namespace) {
        continue;
      }
      if (entry.isExpired(now)) {
        _revocations.remove(entry.taskId);
        expired.add(entry.taskId);
        continue;
      }
      final current = _revocations[entry.taskId];
      if (current != null && entry.version <= current.version) {
        ignored.add(entry.taskId);
        continue;
      }
      _revocations[entry.taskId] = entry;
      if (entry.version > _latestRevocationVersion) {
        _latestRevocationVersion = entry.version;
      }
      applied.add(entry.taskId);
      if (_activeDeliveries.containsKey(entry.taskId)) {
        inflight.add(entry.taskId);
      }
    }

    _pruneExpiredLocalRevocations(now);

    return {
      'tasks': applied,
      'revoked': applied.length,
      if (inflight.isNotEmpty) 'inflight': inflight,
      if (ignored.isNotEmpty) 'ignored': ignored,
      if (expired.isNotEmpty) 'expired': expired,
    };
  }

  void _startControlPlane() {
    final controlQueues = <String>{
      ControlQueueNames.worker(namespace, _workerIdentifier),
      ControlQueueNames.broadcast(namespace),
    };
    for (final queueName in controlQueues) {
      if (_subscriptions.containsKey(queueName)) {
        continue;
      }
      final stream = broker.consume(
        RoutingSubscription.singleQueue(queueName),
        prefetch: 1,
        consumerName: '$_workerIdentifier-control',
      );
      final subscription = stream.listen(
        (delivery) => unawaited(_processControlCommandDelivery(delivery)),
        onError: (error, stack) {
          stemLogger.warning(
            'Control channel error: $error',
            Context(
              _logContext({'queue': queueName, 'stack': stack.toString()}),
            ),
          );
        },
      );
      _subscriptions[queueName] = subscription;
    }
  }

  Future<void> _processControlCommandDelivery(Delivery delivery) async {
    try {
      final envelope = delivery.envelope;
      if (envelope.name != ControlEnvelopeTypes.command) {
        await broker.ack(delivery);
        return;
      }
      final command = controlCommandFromEnvelope(envelope);
      await _handleControlCommand(command);
      await broker.ack(delivery);
    } catch (error, stack) {
      stemLogger.warning(
        'Failed to process control command: $error',
        Context(_logContext({'stack': stack.toString()})),
      );
      try {
        await broker.ack(delivery);
      } catch (_) {}
    }
  }

  Future<void> _handleControlCommand(ControlCommandMessage command) async {
    await _signals.controlCommandReceived(_workerInfoSnapshot, command);

    ControlReplyMessage reply;
    try {
      switch (command.type) {
        case 'ping':
          reply = ControlReplyMessage(
            requestId: command.requestId,
            workerId: _workerIdentifier,
            status: 'ok',
            payload: {
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'queue': primaryQueue,
              'inflight': _inflight,
              'subscriptions': _subscriptionMetadata(),
            },
          );
          break;
        case 'stats':
          reply = ControlReplyMessage(
            requestId: command.requestId,
            workerId: _workerIdentifier,
            status: 'ok',
            payload: _buildStatsSnapshot(),
          );
          break;
        case 'inspect':
          final includeRevoked = command.payload['includeRevoked'] != false;
          reply = ControlReplyMessage(
            requestId: command.requestId,
            workerId: _workerIdentifier,
            status: 'ok',
            payload: _buildInspectSnapshot(includeRevoked: includeRevoked),
          );
          break;
        case 'revoke':
          try {
            final result = await _processRevokeCommand(command);
            reply = ControlReplyMessage(
              requestId: command.requestId,
              workerId: _workerIdentifier,
              status: 'ok',
              payload: result,
            );
          } catch (error, stack) {
            stemLogger.warning(
              'Failed to apply revocations: $error',
              Context(_logContext({'stack': stack.toString()})),
            );
            reply = ControlReplyMessage(
              requestId: command.requestId,
              workerId: _workerIdentifier,
              status: 'error',
              error: {
                'message': 'Failed to apply revocations',
                'detail': error.toString(),
              },
            );
          }
          break;
        case 'shutdown':
          final mode = _parseShutdownMode(command.payload['mode'] as String?);
          final summary = await _handleShutdownRequest(mode);
          reply = ControlReplyMessage(
            requestId: command.requestId,
            workerId: _workerIdentifier,
            status: 'ok',
            payload: summary,
          );
          break;
        default:
          reply = ControlReplyMessage(
            requestId: command.requestId,
            workerId: _workerIdentifier,
            status: 'error',
            error: {'message': 'Unknown control command ${command.type}'},
          );
      }
    } catch (error, stack) {
      stemLogger.warning(
        'Control command handler failed: $error',
        Context(_logContext({'stack': stack.toString()})),
      );
      reply = ControlReplyMessage(
        requestId: command.requestId,
        workerId: _workerIdentifier,
        status: 'error',
        error: {'message': error.toString(), 'stack': stack.toString()},
      );
    }

    await _sendControlReply(reply);
    await _signals.controlCommandCompleted(
      _workerInfoSnapshot,
      command,
      status: reply.status,
      response: reply.payload.isNotEmpty ? reply.payload : null,
      error: reply.error,
    );
  }

  Future<void> _sendControlReply(ControlReplyMessage reply) async {
    final queueName = ControlQueueNames.reply(namespace, reply.requestId);
    try {
      await broker.publish(reply.toEnvelope(queue: queueName));
    } catch (error, stack) {
      stemLogger.warning(
        'Failed to publish control reply: $error',
        Context(_logContext({'queue': queueName, 'stack': stack.toString()})),
      );
    }
  }

  Map<String, Object?> _subscriptionMetadata() => {
    'queues': subscriptionQueues,
    if (subscriptionBroadcasts.isNotEmpty) 'broadcasts': subscriptionBroadcasts,
  };

  Map<String, Object?> _buildStatsSnapshot() {
    final now = DateTime.now().toUtc();
    final activeTasks = _activeDeliveries.entries.map((entry) {
      final delivery = entry.value;
      final envelope = delivery.envelope;
      final runtime = now.difference(delivery.startedAt);
      return {
        'id': envelope.id,
        'task': envelope.name,
        'queue': delivery.queue,
        'attempt': envelope.attempt,
        'runtimeMs': runtime.inMilliseconds,
        'startedAt': delivery.startedAt.toIso8601String(),
      };
    }).toList();

    final queues = Map<String, int>.from(_inflightPerQueue);

    return {
      'timestamp': now.toIso8601String(),
      'namespace': namespace,
      'queue': primaryQueue,
      'host': Platform.localHostname,
      'pid': pid,
      'concurrency': _currentConcurrency,
      'maxConcurrency': concurrency,
      'autoscaleEnabled': autoscaleConfig.enabled,
      'prefetch': prefetch,
      'inflight': _inflight,
      'queues': queues,
      'active': activeTasks,
      'subscriptions': _subscriptionMetadata(),
      'lastLeaseRenewalMsAgo': _lastLeaseRenewal == null
          ? null
          : now.difference(_lastLeaseRenewal!).inMilliseconds,
      'lastQueueDepth': _lastQueueDepth,
    };
  }

  Map<String, Object?> _buildInspectSnapshot({bool includeRevoked = true}) {
    final now = DateTime.now().toUtc();
    final active = _activeDeliveries.values.map((delivery) {
      final envelope = delivery.envelope;
      final runtime = now.difference(delivery.startedAt);
      final leaseAge = delivery.lastLeaseRenewal != null
          ? now.difference(delivery.lastLeaseRenewal!)
          : null;
      return {
        'id': envelope.id,
        'task': envelope.name,
        'queue': delivery.queue,
        'attempt': envelope.attempt,
        'runtimeMs': runtime.inMilliseconds,
        'startedAt': delivery.startedAt.toIso8601String(),
        if (leaseAge != null) 'lastLeaseRenewalMsAgo': leaseAge.inMilliseconds,
        'status': 'running',
      };
    }).toList();

    final revoked = includeRevoked
        ? _revocations.values
              .where((entry) => !entry.isExpired(now))
              .map((entry) => entry.toJson())
              .toList()
        : const [];

    return {
      'timestamp': now.toIso8601String(),
      'inflight': _inflight,
      'active': active,
      if (includeRevoked) 'revoked': revoked,
    };
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
    final pool = TaskIsolatePool(
      size: _currentConcurrency,
      onRecycle: _handleIsolateRecycle,
      onSpawned: (isolateId) {
        unawaited(
          _signals.workerChildLifecycle(
            _workerInfoSnapshot,
            isolateId,
            initializing: true,
          ),
        );
      },
      onDisposed: (isolateId) {
        unawaited(
          _signals.workerChildLifecycle(
            _workerInfoSnapshot,
            isolateId,
            initializing: false,
          ),
        );
      },
    );
    pool.updateRecyclePolicy(
      maxTasksPerIsolate: lifecycleConfig.maxTasksPerIsolate,
      maxMemoryBytes: lifecycleConfig.maxMemoryPerIsolateBytes,
    );
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

  static WorkerAutoscaleConfig _resolveAutoscaleConfig(
    WorkerAutoscaleConfig? provided,
    int normalizedConcurrency,
  ) {
    if (provided == null || !provided.enabled) {
      return const WorkerAutoscaleConfig.disabled();
    }
    final min = math.max(1, provided.minConcurrency);
    final rawMax = provided.maxConcurrency ?? normalizedConcurrency;
    final max = math.max(min, math.min(rawMax, normalizedConcurrency));
    final scaleUpStep = math.max(1, provided.scaleUpStep);
    final scaleDownStep = math.max(1, provided.scaleDownStep);
    final backlogPerIsolate = provided.backlogPerIsolate <= 0
        ? 1.0
        : provided.backlogPerIsolate;
    final tick = provided.tick <= const Duration(milliseconds: 100)
        ? const Duration(seconds: 1)
        : provided.tick;
    final idle = provided.idlePeriod <= Duration.zero
        ? const Duration(seconds: 30)
        : provided.idlePeriod;
    final upCooldown = provided.scaleUpCooldown <= Duration.zero
        ? const Duration(seconds: 1)
        : provided.scaleUpCooldown;
    final downCooldown = provided.scaleDownCooldown <= Duration.zero
        ? const Duration(seconds: 1)
        : provided.scaleDownCooldown;
    return WorkerAutoscaleConfig(
      enabled: true,
      minConcurrency: math.min(min, max),
      maxConcurrency: max,
      scaleUpStep: scaleUpStep,
      scaleDownStep: scaleDownStep,
      backlogPerIsolate: backlogPerIsolate,
      idlePeriod: idle,
      tick: tick,
      scaleUpCooldown: upCooldown,
      scaleDownCooldown: downCooldown,
    );
  }
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

  /// Task was revoked before or during execution.
  revoked,

  /// An error occurred outside task execution.
  error,
}

class TaskRevokedException implements Exception {
  TaskRevokedException({required this.taskId, this.reason, this.requestedBy});

  final String taskId;
  final String? reason;
  final String? requestedBy;

  @override
  String toString() => 'Task $taskId revoked';
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
  _ActiveDelivery({
    required this.queue,
    required this.startedAt,
    required this.envelope,
    required this.delivery,
  });

  /// The queue this delivery belongs to.
  final String queue;

  /// When the task started.
  final DateTime startedAt;

  /// The original envelope for this task.
  final Envelope envelope;

  /// The underlying delivery from the broker.
  final Delivery delivery;

  /// The last lease renewal time.
  DateTime? lastLeaseRenewal;
}
