import 'dart:async';

/// Why a scheduler-neutral worker invocation stopped admitting deliveries.
enum WorkerRunStopReason {
  /// No delivery lifecycle was active for the configured idle interval.
  ///
  /// This is an observation of a subscription, not proof the queue is empty.
  idle,

  /// The admission portion of the execution budget elapsed.
  budgetExceeded,

  /// The caller requested cancellation or shut down the runtime.
  cancelled,

  /// Startup, consumption, or delivery infrastructure failed.
  ///
  /// Ordinary task failures handled by the worker's retry policy are separate.
  failed,
}

/// Result of a one-shot worker invocation, after execution has quiesced.
class WorkerRunOutcome {
  /// Creates an invocation outcome.
  const WorkerRunOutcome({
    required this.reason,
    required this.deliveriesProcessed,
    required this.elapsed,
    this.error,
    this.stackTrace,
  });

  /// Reason admission stopped; this does not describe individual task results.
  final WorkerRunStopReason reason;

  /// Number of admitted delivery lifecycles that finished.
  ///
  /// Includes retries, failures, and recovery of already-terminal deliveries.
  /// It is not a count of successful tasks or successful acknowledgements.
  final int deliveriesProcessed;

  /// Wall-clock execution time, including drain and worker shutdown.
  ///
  /// This can exceed the budget when handlers or infrastructure are slow.
  final Duration elapsed;

  /// Infrastructure error, when [reason] is [WorkerRunStopReason.failed].
  final Object? error;

  /// Stack trace associated with [error].
  final StackTrace? stackTrace;
}

/// Internal admission and idle state for one invocation.
///
/// Activity is measured around complete delivery Futures, never task events or
/// queue counts. The owner must cancel subscriptions and drain before
/// returning.
class WorkerRunState {
  /// Starts the budget clock and attaches the optional cancellation signal.
  WorkerRunState({
    required Duration budget,
    required Duration shutdownReserve,
    required this.idleTimeout,
    Future<void>? cancellation,
  }) : admissionBudget = budget - shutdownReserve {
    validate(budget, shutdownReserve, idleTimeout);
    _clock.start();
    _budgetTimer = Timer(
      admissionBudget,
      () => stop(WorkerRunStopReason.budgetExceeded),
    );
    if (cancellation != null) {
      unawaited(
        cancellation.then(
          (_) => stop(WorkerRunStopReason.cancelled),
          onError: fail,
        ),
      );
    }
  }

  /// Rejects invalid windows before ownership is acquired.
  static void validate(
    Duration budget,
    Duration shutdownReserve,
    Duration idleTimeout,
  ) {
    if (shutdownReserve < Duration.zero || budget <= shutdownReserve) {
      throw ArgumentError('budget must be greater than shutdownReserve >= 0');
    }
    if (idleTimeout <= Duration.zero) {
      throw ArgumentError.value(idleTimeout, 'idleTimeout', 'must be positive');
    }
  }

  /// Maximum time during which new deliveries can be admitted.
  final Duration admissionBudget;

  /// Quiet interval after the last complete delivery lifecycle.
  final Duration idleTimeout;
  final Stopwatch _clock = Stopwatch();
  final Completer<void> _stopped = Completer<void>();
  Timer? _budgetTimer;
  Timer? _idleTimer;
  bool _ready = false;
  bool _disposed = false;
  int _pending = 0;
  int _processed = 0;
  WorkerRunStopReason? _reason;
  Object? _error;
  StackTrace? _stack;

  /// Completes as soon as admission must stop, not when drain finishes.
  Future<void> get stopped => _stopped.future;

  /// Whether another delivery may enter the worker.
  bool get accepting {
    if (_reason == null && _clock.elapsed >= admissionBudget) {
      stop(WorkerRunStopReason.budgetExceeded);
    }
    return _reason == null;
  }

  /// Enables idle detection once startup has finished.
  void ready() {
    _ready = true;
    _armIdle();
  }

  /// Registers admission before any asynchronous delivery work starts.
  bool admit() {
    if (!accepting) return false;
    _pending += 1;
    _idleTimer?.cancel();
    return true;
  }

  /// Records completion of the entire delivery Future.
  void finished() {
    _pending -= 1;
    _processed += 1;
    _armIdle();
  }

  void _armIdle() {
    if (!_ready || _pending != 0 || !accepting) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => stop(WorkerRunStopReason.idle));
  }

  /// Stops admission synchronously. First stop reason wins unless a failure
  /// occurs while draining.
  void stop(WorkerRunStopReason reason) {
    if (_disposed || _reason != null) return;
    _reason = reason;
    _budgetTimer?.cancel();
    _idleTimer?.cancel();
    _stopped.complete();
  }

  /// Records an infrastructure failure, including one discovered during drain.
  void fail(Object error, StackTrace stack) {
    if (_disposed) return;
    _error ??= error;
    _stack ??= stack;
    stop(WorkerRunStopReason.failed);
    _reason = WorkerRunStopReason.failed;
  }

  /// Freezes the outcome and detaches the invocation from late cancellation.
  WorkerRunOutcome finish() {
    _disposed = true;
    _budgetTimer?.cancel();
    _idleTimer?.cancel();
    _clock.stop();
    return WorkerRunOutcome(
      reason: _reason!,
      deliveriesProcessed: _processed,
      elapsed: _clock.elapsed,
      error: _error,
      stackTrace: _stack,
    );
  }
}
