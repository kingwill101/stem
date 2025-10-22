import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;

import '../core/task_invocation.dart';
import 'isolate_messages.dart';

/// A handler for task control signals.
typedef TaskControlHandler = FutureOr<void> Function(
    TaskInvocationSignal signal);

/// Reason an isolate was recycled or disposed.
enum IsolateRecycleReason { scaleDown, maxTasks, memory, shutdown }

/// Metadata describing an isolate recycle event.
class IsolateRecycleEvent {
  IsolateRecycleEvent({
    required this.reason,
    required this.tasksExecuted,
    this.memoryBytes,
  });

  /// Why the isolate was recycled.
  final IsolateRecycleReason reason;

  /// Number of tasks the isolate executed before recycling.
  final int tasksExecuted;

  /// The most recent resident set size reading, if available.
  final int? memoryBytes;
}

/// A pool of isolates for executing tasks concurrently.
///
/// Manages a dynamic number of isolates, queuing jobs when all isolates are
/// busy. The pool can scale up or down at runtime and enforces optional recycle
/// policies such as max tasks or memory per isolate.
class TaskIsolatePool {
  /// Creates a pool with the provided initial [size].
  TaskIsolatePool({
    required int size,
    this.onRecycle,
    this.onSpawned,
    this.onDisposed,
  }) : _targetSize = math.max(1, size);

  final void Function(IsolateRecycleEvent event)? onRecycle;
  final FutureOr<void> Function(int isolateId)? onSpawned;
  final FutureOr<void> Function(int isolateId)? onDisposed;

  int _targetSize;
  final List<_PoolEntry> _idle = <_PoolEntry>[];
  final Queue<_TaskJob> _queue = Queue<_TaskJob>();
  final Set<_PoolEntry> _active = <_PoolEntry>{};
  bool _started = false;
  bool _disposed = false;
  int _pendingDisposals = 0;
  int? _maxTasksPerIsolate;
  int? _maxMemoryBytes;

  /// The desired number of isolates.
  int get size => _targetSize;

  /// The number of currently active isolates.
  int get activeCount => _active.length;

  /// Total isolates managed by the pool.
  int get totalCount => _idle.length + _active.length;

  /// Starts the pool by spawning [_targetSize] isolates.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _ensureCapacity();
  }

  /// Disposes the pool and all its isolates.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    final entries = {..._idle, ..._active};
    _idle.clear();
    _active.clear();
    _pendingDisposals = 0;
    for (final entry in entries) {
      onRecycle?.call(
        IsolateRecycleEvent(
          reason: IsolateRecycleReason.shutdown,
          tasksExecuted: entry.tasksExecuted,
          memoryBytes: entry.lastRssBytes,
        ),
      );
      await _disposeWorker(entry);
    }
  }

  /// Resizes the pool to [newSize], spawning or draining isolates as needed.
  Future<void> resize(int newSize) async {
    if (_disposed) return;
    final normalized = math.max(1, newSize);
    if (normalized == _targetSize) return;
    _targetSize = normalized;

    if (totalCount < _targetSize) {
      await _ensureCapacity();
      _pump();
      return;
    }

    var surplus = totalCount - _targetSize;
    while (surplus > 0 && _idle.isNotEmpty) {
      final entry = _idle.removeLast();
      surplus -= 1;
      onRecycle?.call(
        IsolateRecycleEvent(
          reason: IsolateRecycleReason.scaleDown,
          tasksExecuted: entry.tasksExecuted,
          memoryBytes: entry.lastRssBytes,
        ),
      );
      await _disposeWorker(entry);
    }

    if (surplus > 0) {
      final draining = _active.where((entry) => !entry.draining).take(surplus);
      for (final entry in draining) {
        entry.draining = true;
      }
      _pendingDisposals += surplus;
    }
  }

  /// Updates recycle thresholds for isolates.
  void updateRecyclePolicy({
    int? maxTasksPerIsolate,
    int? maxMemoryBytes,
  }) {
    _maxTasksPerIsolate = maxTasksPerIsolate;
    _maxMemoryBytes = maxMemoryBytes;
  }

  /// Executes a task in an available isolate.
  ///
  /// Runs the task defined by [entrypoint] with the given [args], [headers],
  /// [meta], and [attempt] number. Calls [onControl] for any control signals.
  /// If [hardTimeout] is provided, the task will timeout after that duration.
  ///
  /// Returns a future that completes with a [TaskExecutionResult].
  Future<TaskExecutionResult> execute(
    TaskEntrypoint entrypoint,
    Map<String, Object?> args,
    Map<String, String> headers,
    Map<String, Object?> meta,
    int attempt,
    TaskControlHandler onControl, {
    Duration? hardTimeout,
    required String taskName,
  }) {
    if (_disposed) {
      return Future.error(StateError('TaskIsolatePool disposed'));
    }
    final job = _TaskJob(
      entrypoint: entrypoint,
      args: args,
      headers: headers,
      meta: meta,
      attempt: attempt,
      onControl: onControl,
      hardTimeout: hardTimeout,
      taskName: taskName,
    );
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  void _pump() {
    if (_disposed) return;
    if (_idle.isEmpty && totalCount < _targetSize) {
      // Spawn additional isolates lazily when needed.
      unawaited(_ensureCapacity().then((_) => _pump()));
      return;
    }
    while (_queue.isNotEmpty && _idle.isNotEmpty) {
      final entry = _idle.removeLast();
      final job = _queue.removeFirst();
      _active.add(entry);
      Timer? hardTimer;

      entry.worker.run(job).then((response) {
        if (job.completer.isCompleted) {
          return;
        }
        if (response is TaskRunSuccess) {
          entry.lastRssBytes = response.memoryBytes;
          job.completer.complete(
            TaskExecutionSuccess(
              response.result,
              memoryBytes: response.memoryBytes,
            ),
          );
        } else if (response is TaskRunFailure) {
          job.completer.complete(
            TaskExecutionFailure(
              _RemoteTaskError(
                response.errorType,
                response.message,
                response.stackTrace,
              ),
              StackTrace.fromString(response.stackTrace),
            ),
          );
        } else {
          job.completer.complete(
            TaskExecutionFailure(
              StateError('Unexpected response: $response'),
              StackTrace.current,
            ),
          );
        }
      }).catchError((error, StackTrace stack) {
        if (!job.completer.isCompleted) {
          job.completer.complete(TaskExecutionFailure(error, stack));
        }
      });

      if (job.hardTimeout != null) {
        hardTimer = Timer(job.hardTimeout!, () {
          if (job.completer.isCompleted) {
            return;
          }
          job.completer.complete(
            TaskExecutionTimeout(
              taskName: job.taskName,
              limit: job.hardTimeout,
            ),
          );
          entry.draining = true;
          unawaited(_disposeWorker(entry));
        });
      }

      job.completer.future.whenComplete(() async {
        hardTimer?.cancel();
        _active.remove(entry);
        entry.tasksExecuted += 1;
        final shouldRecycle = _shouldRecycle(entry);
        if (_disposed) {
          await entry.worker.dispose();
          return;
        }
        if (shouldRecycle) {
          await _disposeEntry(
            entry,
            reason: _determineRecycleReason(entry),
          );
        } else if (_pendingDisposals > 0 && entry.draining) {
          _pendingDisposals -= 1;
          await _disposeEntry(
            entry,
            reason: IsolateRecycleReason.scaleDown,
          );
        } else {
          entry.draining = false;
          _idle.add(entry);
        }
        _pump();
      });
    }
  }

  bool _shouldRecycle(_PoolEntry entry) {
    if (entry.draining) {
      return true;
    }
    if (_maxTasksPerIsolate != null &&
        entry.tasksExecuted >= _maxTasksPerIsolate!) {
      return true;
    }
    if (_maxMemoryBytes != null &&
        entry.lastRssBytes != null &&
        entry.lastRssBytes! >= _maxMemoryBytes!) {
      return true;
    }
    return false;
  }

  IsolateRecycleReason _determineRecycleReason(_PoolEntry entry) {
    if (entry.draining) {
      return IsolateRecycleReason.scaleDown;
    }
    if (_maxTasksPerIsolate != null &&
        entry.tasksExecuted >= _maxTasksPerIsolate!) {
      return IsolateRecycleReason.maxTasks;
    }
    if (_maxMemoryBytes != null &&
        entry.lastRssBytes != null &&
        entry.lastRssBytes! >= _maxMemoryBytes!) {
      return IsolateRecycleReason.memory;
    }
    return IsolateRecycleReason.scaleDown;
  }

  Future<void> _disposeEntry(
    _PoolEntry entry, {
    required IsolateRecycleReason reason,
  }) async {
    onRecycle?.call(
      IsolateRecycleEvent(
        reason: reason,
        tasksExecuted: entry.tasksExecuted,
        memoryBytes: entry.lastRssBytes,
      ),
    );
    await _disposeWorker(entry);
    if (!_disposed && totalCount < _targetSize) {
      await _ensureCapacity();
    }
  }

  Future<void> _ensureCapacity() async {
    if (_disposed) return;
    while (totalCount < _targetSize) {
      final worker = await _IsolateWorker.spawn();
      final entry = _PoolEntry(worker);
      _idle.add(entry);
      _notifySpawned(worker);
    }
  }

  void _notifySpawned(_IsolateWorker worker) {
    final callback = onSpawned;
    if (callback == null) return;
    final result = callback(worker.isolateId);
    if (result is Future) {
      unawaited(result);
    }
  }

  void _notifyDisposed(_IsolateWorker worker) {
    final callback = onDisposed;
    if (callback == null) return;
    final result = callback(worker.isolateId);
    if (result is Future) {
      unawaited(result);
    }
  }

  Future<void> _disposeWorker(_PoolEntry entry) async {
    _notifyDisposed(entry.worker);
    await entry.worker.dispose();
  }
}

/// A job representing a task to be executed in an isolate.
class _TaskJob {
  _TaskJob({
    required this.entrypoint,
    required this.args,
    required this.headers,
    required this.meta,
    required this.attempt,
    required this.onControl,
    this.hardTimeout,
    required this.taskName,
  });

  final TaskEntrypoint entrypoint;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final int attempt;
  final TaskControlHandler onControl;
  final Duration? hardTimeout;
  final String taskName;

  final Completer<TaskExecutionResult> completer =
      Completer<TaskExecutionResult>();
}

/// The result of a task execution.
sealed class TaskExecutionResult {
  const TaskExecutionResult();
}

/// A successful task execution with result [value].
class TaskExecutionSuccess extends TaskExecutionResult {
  const TaskExecutionSuccess(this.value, {this.memoryBytes});

  /// The result value of the task.
  final Object? value;

  /// Last reported resident set size for the isolate, in bytes.
  final int? memoryBytes;
}

/// A failed task execution with [error] and [stackTrace].
class TaskExecutionFailure extends TaskExecutionResult {
  const TaskExecutionFailure(this.error, this.stackTrace);

  /// The error that occurred.
  final Object error;

  /// The stack trace of the error.
  final StackTrace stackTrace;
}

/// A timed-out task execution for [taskName] with optional [limit].
class TaskExecutionTimeout extends TaskExecutionResult {
  const TaskExecutionTimeout({required this.taskName, this.limit});

  /// The name of the task that timed out.
  final String taskName;

  /// The timeout duration limit.
  final Duration? limit;
}

class _PoolEntry {
  _PoolEntry(this.worker);

  final _IsolateWorker worker;
  int tasksExecuted = 0;
  int? lastRssBytes;
  bool draining = false;
}

class _IsolateWorker {
  _IsolateWorker(this._isolate, this._sendPort);

  final Isolate _isolate;
  final SendPort _sendPort;
  bool _disposed = false;

  static Future<_IsolateWorker> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(taskWorkerIsolate, handshake.sendPort);
    final sendPort = await handshake.first as SendPort;
    handshake.close();
    return _IsolateWorker(isolate, sendPort);
  }

  bool get isDisposed => _disposed;
  int get isolateId => _isolate.hashCode;

  Future<TaskRunResponse> run(_TaskJob job) async {
    final replyPort = ReceivePort();
    final controlPort = ReceivePort();

    final controlSub = controlPort.listen((message) async {
      if (message is TaskInvocationSignal) {
        await job.onControl(message);
      }
    });

    final request = TaskRunRequest(
      entrypoint: job.entrypoint,
      args: job.args,
      headers: job.headers,
      meta: job.meta,
      attempt: job.attempt,
      controlPort: controlPort.sendPort,
      replyPort: replyPort.sendPort,
    );

    _sendPort.send(request);

    final response = await replyPort.first;
    await controlSub.cancel();
    controlPort.close();
    replyPort.close();

    if (response is TaskRunResponse) {
      return response;
    }

    throw StateError('Unexpected response from worker isolate: $response');
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      _sendPort.send(TaskWorkerShutdown());
    } catch (_) {}
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// An error that occurred during remote task execution in an isolate.
class _RemoteTaskError implements Exception {
  _RemoteTaskError(this.type, this.message, this.stackTrace);

  /// The type of the error.
  final String type;

  /// The error message.
  final String message;

  /// The stack trace of the error.
  final String stackTrace;

  @override
  String toString() => '$type: $message\n$stackTrace';
}
