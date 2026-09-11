import 'dart:async';

/// Internal ownership scopes for detecting a worker joining its own work.
///
/// The marker expires when the operation settles. A later callback inheriting
/// its zone must not be mistaken for a still-active worker operation.
abstract final class WorkerOperationScope {
  static final Object _key = Object();

  /// Whether the caller is part of an operation that [owner] must drain.
  static bool isActiveFor(Object owner) {
    final scope = Zone.current[_key];
    return scope is _Operation && scope.active && identical(scope.owner, owner);
  }

  /// Tracks the lifetime of a worker-owned operation.
  static Future<T> run<T>(Object owner, Future<T> Function() operation) {
    final scope = _Operation(owner);
    return runZoned(() async {
      try {
        return await operation();
      } finally {
        scope.active = false;
      }
    }, zoneValues: {_key: scope});
  }

  /// Gives an underlying inline Future its own lifetime, beyond any timeout
  /// applied by its caller to the enclosing delivery operation.
  static Future<T> runInherited<T>(Future<T> Function() operation) {
    final scope = Zone.current[_key];
    return scope is _Operation
        ? run(scope.owner, operation)
        : Future<T>.sync(operation);
  }
}

class _Operation {
  _Operation(this.owner);

  final Object owner;
  bool active = true;
}
