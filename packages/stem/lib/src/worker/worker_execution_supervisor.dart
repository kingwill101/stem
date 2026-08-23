import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/worker/isolate_pool.dart';
import 'package:stem/src/worker/worker_config.dart';

/// Owns isolate-backed task execution and its pool lifecycle for a worker.
///
/// Delivery acknowledgement, task state persistence, retries, and revocation
/// remain the responsibility of the owning worker. Keeping this boundary
/// focused makes
/// the execution guarantee explicit: isolate handlers can be terminated by
/// disposing their isolate, while inline handlers can only stop being awaited
/// after a timeout.
class WorkerExecutionSupervisor {
  /// Creates an execution supervisor with the worker's isolate settings.
  WorkerExecutionSupervisor({
    required int concurrency,
    required WorkerLifecycleConfig lifecycle,
    required void Function(IsolateRecycleEvent event) onRecycle,
    required FutureOr<void> Function(int isolateId) onSpawned,
    required FutureOr<void> Function(int isolateId) onDisposed,
  }) : _concurrency = concurrency,
       _lifecycle = lifecycle,
       _onRecycle = onRecycle,
       _onSpawned = onSpawned,
       _onDisposed = onDisposed;

  int _concurrency;
  final WorkerLifecycleConfig _lifecycle;
  final void Function(IsolateRecycleEvent event) _onRecycle;
  final FutureOr<void> Function(int isolateId) _onSpawned;
  final FutureOr<void> Function(int isolateId) _onDisposed;

  TaskIsolatePool? _pool;
  Future<TaskIsolatePool>? _poolFuture;
  bool _disposed = false;

  /// Number of active isolates, or zero before the pool is created.
  int get activeIsolates => _pool?.activeCount ?? 0;

  /// Executes [handler] according to its declared [TaskExecutionMode].
  Future<Object?> execute({
    required TaskHandler<Object?> handler,
    required TaskContext context,
    required Envelope envelope,
    required Map<String, Object?> args,
    required TaskControlHandler controlHandler,
    Duration? hardTimeout,
  }) async {
    if (handler.executionMode == TaskExecutionMode.inline) {
      final future = handler.call(context, args);
      if (hardTimeout == null) return future;
      return future.timeout(
        hardTimeout,
        onTimeout: () => throw TimeoutException(
          'hard time limit exceeded for ${handler.name}',
        ),
      );
    }

    final entrypoint = handler.isolateEntrypoint;
    if (entrypoint == null) {
      throw StateError(
        'Task "${handler.name}" declares isolate execution but does not '
        'provide an isolateEntrypoint.',
      );
    }

    final outcome = await (await _ensurePool()).execute(
      entrypoint,
      args,
      envelope.headers,
      envelope.meta,
      envelope.attempt,
      controlHandler,
      taskName: handler.name,
      taskId: envelope.id,
      hardTimeout: hardTimeout,
    );

    if (outcome is TaskExecutionSuccess) return outcome.value;
    if (outcome is TaskExecutionRetry) throw outcome.request;
    if (outcome is TaskExecutionFailure) {
      Error.throwWithStackTrace(outcome.error, outcome.stackTrace);
    }
    if (outcome is TaskExecutionTimeout) {
      throw TimeoutException(
        'hard time limit exceeded for ${outcome.taskName}',
        outcome.limit,
      );
    }

    throw StateError('Unexpected execution outcome: $outcome');
  }

  /// Resizes an already-created pool, if one exists.
  Future<void> resize(int concurrency) async {
    _concurrency = concurrency;
    await _pool?.resize(concurrency);
  }

  /// Disposes the isolate pool and clears its lazy creation state.
  Future<void> dispose() async {
    _disposed = true;
    final pool = _pool;
    final pending = _poolFuture;
    _pool = null;
    _poolFuture = null;
    var resolvedPool = pool;
    if (resolvedPool == null && pending != null) {
      try {
        resolvedPool = await pending;
      } on Object {
        // Pool creation failures are already reported to the execution
        // future; shutdown should still complete and release its state.
      }
    }
    if (resolvedPool != null) await resolvedPool.dispose();
  }

  Future<TaskIsolatePool> _ensurePool() {
    if (_disposed) {
      throw StateError('Task execution supervisor has been disposed.');
    }
    final existing = _pool;
    if (existing != null) return Future.value(existing);
    final pending = _poolFuture;
    if (pending != null) return pending;
    final creation = _createPool();
    _poolFuture = creation;
    return creation;
  }

  Future<TaskIsolatePool> _createPool() async {
    final pool =
        TaskIsolatePool(
          size: _concurrency,
          onRecycle: _onRecycle,
          onSpawned: _onSpawned,
          onDisposed: _onDisposed,
        )..updateRecyclePolicy(
          maxTasksPerIsolate: _lifecycle.maxTasksPerIsolate,
          maxMemoryBytes: _lifecycle.maxMemoryPerIsolateBytes,
        );
    await pool.start();
    if (_disposed) {
      await pool.dispose();
      throw StateError('Task execution supervisor was disposed during start.');
    }
    _pool = pool;
    return pool;
  }
}
