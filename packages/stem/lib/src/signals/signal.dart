import 'dart:async';

/// Signature for signal handlers.
typedef SignalHandler<T> =
    FutureOr<void> Function(T payload, SignalContext context);

/// Predicate used to filter signal payloads.
typedef SignalPredicate<T> = bool Function(T payload, SignalContext context);

/// Context passed to every signal dispatch.
class SignalContext {
  /// Creates a signal dispatch context.
  SignalContext({required this.name, this.sender, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// Signal identifier.
  final String name;

  /// Optional sender identifying the component emitting the signal.
  final String? sender;

  /// Time when dispatch started.
  final DateTime timestamp;

  bool _cancelled = false;

  /// Marks the signal as cancelled, preventing handlers with lower priority
  /// from executing.
  void cancel() {
    _cancelled = true;
  }

  /// Whether subsequent handlers should be skipped.
  bool get isCancelled => _cancelled;
}

/// Configuration applied to all signals dispatched through `SignalHub`.
class SignalDispatchConfig {
  /// Creates signal dispatch configuration.
  const SignalDispatchConfig({this.enabled = true, this.onError});

  /// Whether dispatch is enabled.
  final bool enabled;

  /// Error reporting callback.
  final void Function(String signalName, Object error, StackTrace stackTrace)?
  onError;

  /// Returns a copy of this config with updated values.
  SignalDispatchConfig copyWith({
    bool? enabled,
    void Function(String, Object, StackTrace)? onError,
  }) {
    return SignalDispatchConfig(
      enabled: enabled ?? this.enabled,
      onError: onError ?? this.onError,
    );
  }
}

/// Handle representing a registered signal listener.
class SignalSubscription {
  /// Creates a subscription that can be cancelled.
  const SignalSubscription._(this._disconnect);

  final void Function() _disconnect;

  /// Cancels the subscription and stops receiving signals.
  void cancel() => _disconnect();
}

/// Filters signal emissions based on payload and context.
class SignalFilter<T> {
  /// Creates a filter using [predicate].
  factory SignalFilter.where(SignalPredicate<T> predicate) =>
      SignalFilter<T>._(predicate);
  const SignalFilter._(this._predicate);

  final SignalPredicate<T> _predicate;

  static bool _alwaysTrue<T>(T _, SignalContext _) => true;

  /// Allows all payloads through the filter.
  static SignalFilter<T> allowAll<T>() => SignalFilter<T>._(_alwaysTrue);

  /// Returns whether the [payload] passes the filter.
  bool matches(T payload, SignalContext context) =>
      _predicate(payload, context);

  /// Combines this filter with [other] using logical AND.
  SignalFilter<T> and(SignalFilter<T> other) => SignalFilter<T>._(
    (payload, context) =>
        matches(payload, context) && other.matches(payload, context),
  );

  /// Negates this filter.
  SignalFilter<T> negate() =>
      SignalFilter<T>._((payload, context) => !matches(payload, context));
}

/// Dispatchable signal with typed payloads and listener management.
class Signal<T> {
  /// Creates a signal with the given [name] and default filter.
  Signal({
    required this.name,
    SignalFilter<T>? defaultFilter,
    this.config = const SignalDispatchConfig(),
  }) : _defaultFilter = defaultFilter ?? SignalFilter.allowAll<T>();

  /// Signal name used for logging and dispatch.
  final String name;

  final SignalFilter<T> _defaultFilter;

  /// Dispatch configuration for this signal.
  SignalDispatchConfig config;

  final List<_Listener<T>> _listeners = <_Listener<T>>[];

  /// Whether any listeners are currently registered.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers a [handler] and returns a cancellable subscription.
  SignalSubscription connect(
    SignalHandler<T> handler, {
    SignalFilter<T>? filter,
    bool once = false,
    int priority = 0,
  }) {
    final listener = _Listener<T>(
      handler: handler,
      filter: filter ?? _defaultFilter,
      once: once,
      priority: priority,
    );
    _listeners
      ..add(listener)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return SignalSubscription._(() {
      _listeners.remove(listener);
    });
  }

  /// Emits the signal to all matching listeners.
  Future<void> emit(T payload, {String? sender}) async {
    if (!config.enabled || _listeners.isEmpty) {
      return;
    }

    final context = SignalContext(name: name, sender: sender);
    final snapshot = List<_Listener<T>>.from(_listeners);
    for (final listener in snapshot) {
      if (!_listeners.contains(listener)) {
        continue;
      }
      if (!listener.filter.matches(payload, context)) {
        continue;
      }
      try {
        await listener.handler(payload, context);
      } on Object catch (error, stackTrace) {
        config.onError?.call(name, error, stackTrace);
      } finally {
        if (listener.once) {
          _listeners.remove(listener);
        }
      }
      if (context.isCancelled) {
        break;
      }
    }
  }
}

class _Listener<T> {
  _Listener({
    required this.handler,
    required this.filter,
    required this.once,
    required this.priority,
  });

  final SignalHandler<T> handler;
  final SignalFilter<T> filter;
  final bool once;
  final int priority;
}
