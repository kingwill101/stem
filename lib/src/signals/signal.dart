import 'dart:async';

typedef SignalHandler<T> = FutureOr<void> Function(
  T payload,
  SignalContext context,
);

typedef SignalPredicate<T> = bool Function(
  T payload,
  SignalContext context,
);

/// Context passed to every signal dispatch.
class SignalContext {
  SignalContext({
    required this.name,
    this.sender,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

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

/// Configuration applied to all signals dispatched through [SignalHub].
class SignalDispatchConfig {
  const SignalDispatchConfig({
    this.enabled = true,
    this.onError,
  });

  /// Whether dispatch is enabled.
  final bool enabled;

  /// Error reporting callback.
  final void Function(
    String signalName,
    Object error,
    StackTrace stackTrace,
  )? onError;

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

class SignalSubscription {
  const SignalSubscription._(this._disconnect);

  final void Function() _disconnect;

  void cancel() => _disconnect();
}

class SignalFilter<T> {
  const SignalFilter._(this._predicate);

  final SignalPredicate<T> _predicate;

  static bool _alwaysTrue<T>(T _, SignalContext __) => true;

  /// Allows all payloads through the filter.
  static SignalFilter<T> allowAll<T>() => SignalFilter<T>._(_alwaysTrue);

  /// Creates a filter using [predicate].
  factory SignalFilter.where(SignalPredicate<T> predicate) =>
      SignalFilter<T>._(predicate);

  bool matches(T payload, SignalContext context) =>
      _predicate(payload, context);

  SignalFilter<T> and(SignalFilter<T> other) => SignalFilter<T>._(
        (payload, context) =>
            matches(payload, context) && other.matches(payload, context),
      );

  SignalFilter<T> negate() => SignalFilter<T>._(
        (payload, context) => !matches(payload, context),
      );
}

class Signal<T> {
  Signal({
    required this.name,
    SignalFilter<T>? defaultFilter,
    SignalDispatchConfig? config,
  })  : _defaultFilter = defaultFilter ?? SignalFilter.allowAll<T>(),
        _config = config ?? const SignalDispatchConfig();

  final String name;

  final SignalFilter<T> _defaultFilter;

  SignalDispatchConfig _config;

  final List<_Listener<T>> _listeners = <_Listener<T>>[];

  SignalDispatchConfig get config => _config;

  set config(SignalDispatchConfig value) {
    _config = value;
  }

  bool get hasListeners => _listeners.isNotEmpty;

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
    _listeners.add(listener);
    _listeners.sort((a, b) => b.priority.compareTo(a.priority));
    return SignalSubscription._(() {
      _listeners.remove(listener);
    });
  }

  Future<void> emit(
    T payload, {
    String? sender,
  }) async {
    if (!_config.enabled || _listeners.isEmpty) {
      return;
    }

    final context = SignalContext(name: name, sender: sender);
    final List<_Listener<T>> snapshot = List<_Listener<T>>.from(_listeners);
    for (final listener in snapshot) {
      if (!_listeners.contains(listener)) {
        continue;
      }
      if (!listener.filter.matches(payload, context)) {
        continue;
      }
      try {
        await listener.handler(payload, context);
      } catch (error, stackTrace) {
        _config.onError?.call(name, error, stackTrace);
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
