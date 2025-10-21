import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import '../core/task_invocation.dart';
import 'isolate_messages.dart';

/// A handler for task control signals.
typedef TaskControlHandler = FutureOr<void> Function(
    TaskInvocationSignal signal);

/// A pool of isolates for executing tasks concurrently.
///
/// This class manages a fixed number of isolates to run tasks in parallel,
/// queuing jobs when all isolates are busy.
class TaskIsolatePool {
  /// Creates a pool with [size] isolates.
  TaskIsolatePool({required this.size});

  /// The number of isolates in this pool.
  final int size;
  final List<_IsolateWorker> _idle = [];
  final Queue<_TaskJob> _queue = Queue<_TaskJob>();
  final Set<_IsolateWorker> _active = <_IsolateWorker>{};
  bool _started = false;
  bool _disposed = false;

  /// The number of currently active isolates.
  int get activeCount => _active.length;

  /// Starts the pool by spawning [size] isolates.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (var i = 0; i < size; i++) {
      _idle.add(await _IsolateWorker.spawn());
    }
  }

  /// Disposes the pool and all its isolates.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    final workers = {..._idle, ..._active};
    _idle.clear();
    _active.clear();
    for (final worker in workers) {
      await worker.dispose();
    }
  }

  /// Executes a task in an available isolate.
  ///
  /// Runs the task defined by [entrypoint] with the given [args], [headers],
  /// [meta], and [attempt] number. Calls [onControl] for any control signals.
  /// If [hardTimeout] is provided, the task will timeout after that duration.
  ///
  /// Returns a future that completes with a [TaskExecutionResult].
  /// Throws a [StateError] if the pool is disposed.
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
    while (_queue.isNotEmpty && _idle.isNotEmpty) {
      final worker = _idle.removeLast();
      final job = _queue.removeFirst();
      _active.add(worker);
      Timer? hardTimer;

      worker.run(job).then((value) {
        if (!job.completer.isCompleted) {
          job.completer.complete(TaskExecutionSuccess(value));
        }
      }).catchError((error, StackTrace stack) {
        if (!job.completer.isCompleted) {
          final resolvedStack = error is _RemoteTaskError
              ? StackTrace.fromString(error.stackTrace)
              : stack;
          job.completer.complete(
            TaskExecutionFailure(error, resolvedStack),
          );
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
          unawaited(worker.dispose());
        });
      }

      job.completer.future.whenComplete(() async {
        hardTimer?.cancel();
        _active.remove(worker);
        if (_disposed) {
          await worker.dispose();
          return;
        }
        if (worker.isDisposed) {
          if (!_disposed) {
            final replacement = await _IsolateWorker.spawn();
            _idle.add(replacement);
          }
        } else {
          _idle.add(worker);
        }
        _pump();
      });
    }
  }
}

/// A job representing a task to be executed in an isolate.
class _TaskJob {
  /// Creates a task job with the given parameters.
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

  /// The entrypoint function for the task.
  final TaskEntrypoint entrypoint;

  /// The arguments passed to the task.
  final Map<String, Object?> args;

  /// The headers for the task.
  final Map<String, String> headers;

  /// The metadata for the task.
  final Map<String, Object?> meta;

  /// The attempt number for the task.
  final int attempt;

  /// The handler for task control signals.
  final TaskControlHandler onControl;

  /// The hard timeout duration for the task.
  final Duration? hardTimeout;

  /// The name of the task.
  final String taskName;

  /// The completer for the task execution result.
  final Completer<TaskExecutionResult> completer =
      Completer<TaskExecutionResult>();
}

/// The result of a task execution.
sealed class TaskExecutionResult {
  const TaskExecutionResult();
}

/// A successful task execution with result [value].
class TaskExecutionSuccess extends TaskExecutionResult {
  const TaskExecutionSuccess(this.value);

  /// The result value of the task.
  final Object? value;
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

/// A worker that manages a single isolate for executing tasks.
class _IsolateWorker {
  _IsolateWorker(this._isolate, this._sendPort);

  final Isolate _isolate;
  final SendPort _sendPort;
  bool _disposed = false;

  /// Spawns a new isolate and returns a worker to manage it.
  static Future<_IsolateWorker> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(taskWorkerIsolate, handshake.sendPort);
    final sendPort = await handshake.first as SendPort;
    handshake.close();
    return _IsolateWorker(isolate, sendPort);
  }

  /// Whether this worker has been disposed.
  bool get isDisposed => _disposed;

  /// Runs the given [job] in the isolate and returns the result.
  ///
  /// Throws a [_RemoteTaskError] if the task fails in the isolate.
  Future<Object?> run(_TaskJob job) async {
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

    if (response is TaskRunSuccess) {
      return response.result;
    } else if (response is TaskRunFailure) {
      throw _RemoteTaskError(
        response.errorType,
        response.message,
        response.stackTrace,
      );
    } else {
      throw StateError('Unexpected response from worker isolate: $response');
    }
  }

  /// Disposes this worker and terminates the isolate.
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
