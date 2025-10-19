import 'dart:async';

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../core/retry.dart';
import '../observability/logging.dart';
import '../observability/metrics.dart';

/// Worker daemon that consumes tasks from a broker and executes registered handlers.
class Worker {
  Worker({
    required this.broker,
    required this.registry,
    required this.backend,
    this.rateLimiter,
    this.middleware = const [],
    RetryStrategy? retryStrategy,
    this.queue = 'default',
    this.consumerName,
    this.prefetch = 1,
    this.heartbeatInterval = const Duration(seconds: 15),
  }) : retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy();

  final Broker broker;
  final TaskRegistry registry;
  final ResultBackend backend;
  final RateLimiter? rateLimiter;
  final List<Middleware> middleware;
  final RetryStrategy retryStrategy;
  final String queue;
  final String? consumerName;
  final int prefetch;
  final Duration heartbeatInterval;

  final Map<String, Timer> _leaseTimers = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, StreamSubscription<Delivery>> _subscriptions = {};
  final StreamController<WorkerEvent> _events = StreamController.broadcast();

  bool _running = false;

  Stream<WorkerEvent> get events => _events.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final subscription = broker
        .consume(queue, prefetch: prefetch, consumerName: consumerName)
        .listen(
          (delivery) {
            // Fire-and-forget; handler manages its own lifecycle.
            unawaited(_handle(delivery));
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

  Future<void> shutdown() async {
    _running = false;
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

    await _events.close();
  }

  Future<void> _handle(Delivery delivery) async {
    final envelope = delivery.envelope;
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
            data: {'rateLimited': true, 'retryAfterMs': backoff.inMilliseconds},
          ),
        );
        return;
      }
    }

    final groupId = envelope.headers['stem-group-id'];

    stemLogger.fine('Task ${envelope.name} (${envelope.id}) started');
    StemMetrics.instance.increment(
      'tasks.started',
      tags: {'task': envelope.name, 'queue': envelope.queue},
    );

    await backend.set(
      envelope.id,
      TaskState.running,
      attempt: envelope.attempt,
      meta: {...envelope.meta, 'queue': envelope.queue, 'worker': consumerName},
    );

    final context = TaskContext(
      id: envelope.id,
      attempt: envelope.attempt,
      headers: envelope.headers,
      meta: envelope.meta,
      heartbeat: () => _sendHeartbeat(envelope.id),
      extendLease: (duration) async {
        await broker.extendLease(delivery, duration);
        _restartLeaseTimer(delivery, duration);
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

      result = await _invokeWithMiddleware(
        context,
        () => _executeWithHardLimit(handler, context, envelope.args),
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
        'tasks.succeeded',
        tags: {'task': envelope.name, 'queue': envelope.queue},
      );
      stemLogger.fine('Task ${envelope.name} (${envelope.id}) succeeded');
      _events.add(
        WorkerEvent(type: WorkerEventType.completed, envelope: envelope),
      );
    } catch (error, stack) {
      await _notifyErrorMiddleware(context, error, stack);
      _cancelLeaseTimer(delivery.receipt);
      _heartbeatTimers.remove(envelope.id)?.cancel();
      await _handleFailure(handler, delivery, envelope, error, stack, groupId);
    } finally {
      heartbeatTimer?.cancel();
      softTimer?.cancel();
    }
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
    Map<String, Object?> args,
  ) {
    final hard = handler.options.hardTimeLimit;
    final future = handler.call(context, args);
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
  }

  void _restartLeaseTimer(Delivery delivery, Duration duration) {
    final intervalMs = (duration.inMilliseconds ~/ 2).clamp(1000, 30000);
    _startLeaseTimer(delivery, Duration(milliseconds: intervalMs));
  }

  void _startLeaseTimer(Delivery delivery, Duration interval) {
    _leaseTimers[delivery.receipt]?.cancel();
    final timer = Timer.periodic(interval, (_) async {
      await broker.extendLease(delivery, interval);
    });
    _leaseTimers[delivery.receipt] = timer;
  }

  void _cancelLeaseTimer(String receipt) {
    _leaseTimers.remove(receipt)?.cancel();
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
        'tasks.failed',
        tags: {'task': envelope.name, 'queue': envelope.queue},
      );
      stemLogger.warning(
        'Task ${envelope.name} (${envelope.id}) failed: $error',
        error,
        stack,
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
}

class WorkerEvent {
  WorkerEvent({
    required this.type,
    this.envelope,
    this.envelopeId,
    this.error,
    this.stackTrace,
    this.progress,
    this.data,
  });

  final WorkerEventType type;
  final Envelope? envelope;
  final String? envelopeId;
  final Object? error;
  final StackTrace? stackTrace;
  final double? progress;
  final Map<String, Object?>? data;
}

enum WorkerEventType {
  heartbeat,
  progress,
  timeout,
  completed,
  retried,
  failed,
  error,
}

class _RateSpec {
  const _RateSpec({required this.tokens, required this.period});

  final int tokens;
  final Duration period;
}
