/// Runtime-neutral task processing and semantic outcomes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/encoder_keys.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/retry.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';

/// Runtime callbacks and optional services exposed to an executing task.
class TaskExecutionControl {
  /// Creates execution controls for the current delivery runtime.
  const TaskExecutionControl({
    this.heartbeat = _noopHeartbeat,
    this.extendLease = _noopExtendLease,
    this.progress = _noopProgress,
    this.cancellation = const TaskCancellationToken.none(),
    this.enqueuer,
    this.workflows,
    this.workflowEvents,
  });

  /// Notifies the host that execution remains active.
  final void Function() heartbeat;

  /// Requests additional delivery time from the host.
  final Future<void> Function(Duration by) extendLease;

  /// Reports task progress to the host.
  final Future<void> Function(
    double percentComplete, {
    Map<String, Object?>? data,
  })
  progress;

  /// Cooperative cancellation state supplied by the host.
  final TaskCancellationToken cancellation;

  /// Optional producer used for child task dispatch.
  final TaskEnqueuer? enqueuer;

  /// Optional workflow caller used for child workflows.
  final WorkflowCaller? workflows;

  /// Optional workflow event emitter.
  final WorkflowEventEmitter? workflowEvents;
}

void _noopHeartbeat() {}

Future<void> _noopExtendLease(Duration _) async {}

Future<void> _noopProgress(
  double _, {
  Map<String, Object?>? data,
}) async {}

/// Reason a task envelope was rejected before handler execution.
enum TaskRejectionReason {
  /// No handler is registered for the envelope task name.
  unregisteredTask,

  /// Envelope signature validation failed.
  invalidSignature,

  /// The encoded task arguments could not be decoded safely.
  invalidPayload,
}

/// Reason task processing was cancelled without executing to success.
enum TaskCancellationReason {
  /// The envelope expired before execution began.
  expired,

  /// The runtime or task requested cooperative cancellation.
  cancelled,
}

/// Semantic result of processing one task envelope.
sealed class TaskProcessOutcome {
  const TaskProcessOutcome({required this.envelope});

  /// Effective envelope used for this attempt.
  final Envelope envelope;

  /// Stable logical task identifier retained across every attempt.
  String get taskId => envelope.id;

  /// Zero-based attempt processed by the handler.
  int get attempt => envelope.attempt;
}

/// Successful handler execution.
final class TaskProcessSuccess extends TaskProcessOutcome {
  /// Creates a successful processing outcome.
  const TaskProcessSuccess({required super.envelope, this.value});

  /// Raw value returned by the handler.
  final Object? value;
}

/// Handler execution that should be attempted again later.
final class TaskProcessRetry extends TaskProcessOutcome {
  /// Creates an outcome requesting a later delivery attempt.
  const TaskProcessRetry({
    required super.envelope,
    required this.nextEnvelope,
    required this.delay,
    required this.error,
    required this.stackTrace,
    this.explicit = false,
  });

  /// Envelope metadata for runtimes that retry by republishing.
  final Envelope nextEnvelope;

  /// Requested delay before the next delivery.
  final Duration delay;

  /// Failure or explicit retry request that produced this outcome.
  final Object error;

  /// Stack trace associated with [error].
  final StackTrace stackTrace;

  /// Whether the handler explicitly requested the retry.
  final bool explicit;

  /// Zero-based attempt expected on the next delivery.
  int get nextAttempt => nextEnvelope.attempt;
}

/// Terminal handler failure after retry policy evaluation.
final class TaskProcessFailure extends TaskProcessOutcome {
  /// Creates a terminal failure outcome.
  const TaskProcessFailure({
    required super.envelope,
    required this.error,
    required this.stackTrace,
    this.retryExhausted = false,
  });

  /// Terminal failure.
  final Object error;

  /// Failure stack trace.
  final StackTrace stackTrace;

  /// Whether the outcome exhausted an available retry budget.
  final bool retryExhausted;
}

/// Envelope rejected before handler execution.
final class TaskProcessRejected extends TaskProcessOutcome {
  /// Creates an outcome for an envelope rejected before execution.
  const TaskProcessRejected({
    required super.envelope,
    required this.reason,
    this.error,
    this.stackTrace,
  });

  /// Stable rejection category for transport mapping.
  final TaskRejectionReason reason;

  /// Optional underlying validation or decoding error.
  final Object? error;

  /// Optional error stack trace.
  final StackTrace? stackTrace;
}

/// Task cancelled or expired.
final class TaskProcessCancelled extends TaskProcessOutcome {
  /// Creates an outcome for a cancelled or expired task.
  const TaskProcessCancelled({
    required super.envelope,
    required this.reason,
    this.error,
  });

  /// Cancellation category.
  final TaskCancellationReason reason;

  /// Optional cancellation error.
  final Object? error;
}

/// Duplicate delivery skipped because a terminal status already exists.
final class TaskProcessSkipped extends TaskProcessOutcome {
  /// Creates an outcome for a duplicate terminal delivery.
  const TaskProcessSkipped({
    required super.envelope,
    required this.existingStatus,
  });

  /// Existing terminal state that owns the logical task result.
  final TaskStatus existingStatus;
}

/// Processes a single envelope without owning broker delivery lifecycle.
///
/// The processor performs portable validation, decoding, execution middleware,
/// handler invocation, timeout handling, and retry classification. It never
/// consumes, acknowledges, republishes, dead-letters, or manages a lease.
class TaskProcessor {
  /// Creates a runtime-neutral task processor.
  TaskProcessor({
    required this.registry,
    RetryStrategy? retryStrategy,
    List<Middleware> middleware = const [],
    this.signer,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
    int? randomSeed,
  }) : retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy(),
       middleware = List.unmodifiable(middleware),
       payloadEncoders = ensureTaskPayloadEncoderRegistry(
         encoderRegistry,
         argsEncoder: argsEncoder,
         additionalEncoders: additionalEncoders,
       ),
       _random = math.Random(randomSeed);

  /// Registry used to resolve task handlers.
  final TaskRegistry registry;

  /// Default retry strategy.
  final RetryStrategy retryStrategy;

  /// Execution and error middleware.
  final List<Middleware> middleware;

  /// Optional envelope signer used for verification.
  final PayloadSigner? signer;

  /// Payload encoder registry used to decode durable task arguments.
  final TaskPayloadEncoderRegistry payloadEncoders;

  final math.Random _random;

  /// Processes [envelope] and returns a transport-independent outcome.
  ///
  /// [deliveryAttempt] overrides the envelope attempt for runtimes whose
  /// native retry counter is stored outside the message body. It is zero-based.
  /// [existingStatus] allows the caller to suppress a previously completed
  /// duplicate without giving the processor ownership of persistence.
  Future<TaskProcessOutcome> process(
    Envelope envelope, {
    int? deliveryAttempt,
    TaskStatus? existingStatus,
    TaskExecutionControl control = const TaskExecutionControl(),
  }) async {
    if (deliveryAttempt != null && deliveryAttempt < 0) {
      throw ArgumentError.value(
        deliveryAttempt,
        'deliveryAttempt',
        'must be zero or greater',
      );
    }
    final effectiveEnvelope = deliveryAttempt == null
        ? envelope
        : envelope.copyWith(attempt: deliveryAttempt);

    if (existingStatus?.state.isTerminal ?? false) {
      return TaskProcessSkipped(
        envelope: effectiveEnvelope,
        existingStatus: existingStatus!,
      );
    }

    final handler = registry.resolve(effectiveEnvelope.name);
    if (handler == null) {
      return TaskProcessRejected(
        envelope: effectiveEnvelope,
        reason: TaskRejectionReason.unregisteredTask,
      );
    }

    final resolvedSigner = signer;
    if (resolvedSigner != null) {
      try {
        await resolvedSigner.verify(effectiveEnvelope);
      } on Object catch (error, stackTrace) {
        return TaskProcessRejected(
          envelope: effectiveEnvelope,
          reason: TaskRejectionReason.invalidSignature,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (_isExpired(effectiveEnvelope)) {
      return TaskProcessCancelled(
        envelope: effectiveEnvelope,
        reason: TaskCancellationReason.expired,
      );
    }

    late final Map<String, Object?> decodedArgs;
    try {
      decodedArgs = _decodeArgs(effectiveEnvelope, handler);
    } on Object catch (error, stackTrace) {
      return TaskProcessRejected(
        envelope: effectiveEnvelope,
        reason: TaskRejectionReason.invalidPayload,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final context = TaskContext(
      id: effectiveEnvelope.id,
      args: effectiveEnvelope.args,
      attempt: effectiveEnvelope.attempt,
      headers: effectiveEnvelope.headers,
      meta: effectiveEnvelope.meta,
      heartbeat: control.heartbeat,
      extendLease: control.extendLease,
      progress: control.progress,
      cancellation: control.cancellation,
      enqueuer: control.enqueuer,
      workflows: control.workflows,
      workflowEvents: control.workflowEvents,
    );

    try {
      control.cancellation.throwIfCancelled();
      final value = await _invoke(
        context,
        () => _invokeHandler(
          handler,
          context,
          decodedArgs,
          hardTimeout: _resolveHardTimeLimit(
            effectiveEnvelope,
            handler.options,
          ),
        ),
      );
      return TaskProcessSuccess(envelope: effectiveEnvelope, value: value);
    } on TaskCancellationException catch (error) {
      return TaskProcessCancelled(
        envelope: effectiveEnvelope,
        reason: TaskCancellationReason.cancelled,
        error: error,
      );
    } on TaskRetryRequest catch (request, stackTrace) {
      return _explicitRetry(
        effectiveEnvelope,
        handler,
        request,
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      await _notifyError(context, error, stackTrace);
      return _failureOutcome(
        effectiveEnvelope,
        handler,
        error,
        stackTrace,
      );
    }
  }

  Future<Object?> _invoke(
    TaskContext context,
    Future<Object?> Function() handler,
  ) async {
    Object? result;

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

  Future<Object?> _invokeHandler(
    TaskHandler<Object?> handler,
    TaskContext context,
    Map<String, Object?> args, {
    Duration? hardTimeout,
  }) {
    final future = handler.call(context, args);
    if (hardTimeout == null) return future;
    return future.timeout(
      hardTimeout,
      onTimeout: () => throw TimeoutException(
        'hard time limit exceeded for ${handler.name}',
        hardTimeout,
      ),
    );
  }

  Future<void> _notifyError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  ) async {
    for (final item in middleware) {
      await item.onError(context, error, stackTrace);
    }
  }

  TaskProcessOutcome _explicitRetry(
    Envelope envelope,
    TaskHandler<Object?> handler,
    TaskRetryRequest request,
    StackTrace stackTrace,
  ) {
    final policy =
        request.retryPolicy ?? _resolveRetryPolicy(envelope, handler.options);
    final maxRetries =
        request.maxRetries ?? policy?.maxRetries ?? envelope.maxRetries;
    if (envelope.attempt >= maxRetries) {
      return TaskProcessFailure(
        envelope: envelope,
        error: StateError('retry requested but max retries exceeded'),
        stackTrace: stackTrace,
        retryExhausted: true,
      );
    }

    final now = stemNow();
    final requestedAt =
        request.eta ??
        (request.countdown == null ? null : now.add(request.countdown!));
    final computedDelay = requestedAt == null
        ? _computeRetryDelay(envelope.attempt, request, stackTrace, policy)
        : requestedAt.difference(now);
    final delay = computedDelay.isNegative ? Duration.zero : computedDelay;
    final notBefore = requestedAt ?? now.add(delay);
    final updatedMeta = Map<String, Object?>.from(envelope.meta);
    if (request.timeLimit != null) {
      updatedMeta['stem.timeLimitMs'] = request.timeLimit!.inMilliseconds;
    }
    if (request.softTimeLimit != null) {
      updatedMeta['stem.softTimeLimitMs'] =
          request.softTimeLimit!.inMilliseconds;
    }
    if (request.retryPolicy != null) {
      updatedMeta['stem.retryPolicy'] = request.retryPolicy!.toJson();
    }
    final nextEnvelope = envelope.copyWith(
      attempt: envelope.attempt + 1,
      maxRetries: maxRetries,
      notBefore: notBefore,
      meta: updatedMeta,
    );
    return TaskProcessRetry(
      envelope: envelope,
      nextEnvelope: nextEnvelope,
      delay: delay,
      error: request,
      stackTrace: stackTrace,
      explicit: true,
    );
  }

  TaskProcessOutcome _failureOutcome(
    Envelope envelope,
    TaskHandler<Object?> handler,
    Object error,
    StackTrace stackTrace,
  ) {
    final policy = _resolveRetryPolicy(envelope, handler.options);
    final maxRetries = policy?.maxRetries ?? envelope.maxRetries;
    final canRetry = envelope.attempt < maxRetries;
    if (canRetry && _shouldAutoRetry(policy, error)) {
      final delay = _computeRetryDelay(
        envelope.attempt,
        error,
        stackTrace,
        policy,
      );
      return TaskProcessRetry(
        envelope: envelope,
        nextEnvelope: envelope.copyWith(
          attempt: envelope.attempt + 1,
          maxRetries: maxRetries,
          notBefore: stemNow().add(delay),
        ),
        delay: delay,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return TaskProcessFailure(
      envelope: envelope,
      error: error,
      stackTrace: stackTrace,
      retryExhausted: !canRetry && maxRetries > 0,
    );
  }

  Map<String, Object?> _decodeArgs(
    Envelope envelope,
    TaskHandler<Object?> handler,
  ) {
    final fallback = handler.metadata.argsEncoder;
    payloadEncoders.register(fallback);
    final encoderId =
        envelope.headers[stemArgsEncoderHeader] ??
        (envelope.meta[stemArgsEncoderMetaKey] as String?);
    final encoder = encoderId == null
        ? fallback ?? payloadEncoders.defaultArgsEncoder
        : payloadEncoders.resolveArgs(encoderId);
    final decoded = encoder.decode(envelope.args);
    if (decoded == null) return const {};
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.from(decoded);
    }
    if (decoded is Map) {
      final result = <String, Object?>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        if (key is! String) {
          throw StateError(
            'Task args encoder ${encoder.id} must use string keys, found '
            '$key',
          );
        }
        result[key] = entry.value;
      }
      return result;
    }
    throw StateError(
      'Task args encoder ${encoder.id} must decode to '
      'Map<String, Object?> values, got ${decoded.runtimeType}.',
    );
  }

  bool _isExpired(Envelope envelope) {
    final value = envelope.meta['stem.expiresAt'];
    if (value == null) return false;
    final expiresAt = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());
    return expiresAt != null && stemNow().isAfter(expiresAt);
  }

  Duration? _resolveHardTimeLimit(
    Envelope envelope,
    TaskOptions options,
  ) {
    final value = envelope.meta['stem.timeLimitMs'];
    if (value == null) return options.hardTimeLimit;
    if (value is Duration) return value;
    if (value is num) return Duration(milliseconds: value.toInt());
    final milliseconds = num.tryParse(value.toString());
    return milliseconds == null
        ? options.hardTimeLimit
        : Duration(milliseconds: milliseconds.toInt());
  }

  TaskRetryPolicy? _resolveRetryPolicy(
    Envelope envelope,
    TaskOptions handlerOptions,
  ) {
    final override = envelope.meta['stem.retryPolicy'];
    if (override is TaskRetryPolicy) return override;
    if (override is Map) {
      return TaskRetryPolicy.fromJson(override.cast<String, Object?>());
    }
    return handlerOptions.retryPolicy;
  }

  bool _shouldAutoRetry(TaskRetryPolicy? policy, Object error) {
    if (policy == null) return true;
    final errorType = error.runtimeType.toString();
    bool matches(List<Object> filters) =>
        filters.any((value) => value.toString() == errorType);
    if (policy.dontAutoRetryFor.isNotEmpty &&
        matches(policy.dontAutoRetryFor)) {
      return false;
    }
    return policy.autoRetryFor.isEmpty || matches(policy.autoRetryFor);
  }

  Duration _computeRetryDelay(
    int attempt,
    Object error,
    StackTrace stackTrace,
    TaskRetryPolicy? policy,
  ) {
    if (policy == null) {
      return retryStrategy.nextDelay(attempt, error, stackTrace);
    }
    final base = policy.defaultDelay ?? Duration.zero;
    if (!policy.backoff) return base;
    final rawMilliseconds = base.inMilliseconds == 0
        ? 0
        : base.inMilliseconds * (1 << attempt);
    final capMilliseconds =
        policy.backoffMax?.inMilliseconds ?? rawMilliseconds;
    final capped = rawMilliseconds == 0
        ? capMilliseconds
        : rawMilliseconds.clamp(0, capMilliseconds);
    if (!policy.jitter || capped == 0) {
      return Duration(milliseconds: capped);
    }
    final jitter = _random.nextInt((capped ~/ 4) + 1);
    return Duration(
      milliseconds: (capped - jitter).clamp(0, capMilliseconds),
    );
  }
}
