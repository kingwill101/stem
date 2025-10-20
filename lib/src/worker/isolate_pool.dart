import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import '../core/task_invocation.dart';
import 'isolate_messages.dart';

typedef TaskControlHandler =
    FutureOr<void> Function(TaskInvocationSignal signal);

class TaskIsolatePool {
  TaskIsolatePool({required this.size});

  final int size;
  final List<_IsolateWorker> _idle = [];
  final Queue<_TaskJob> _queue = Queue<_TaskJob>();
  final Set<_IsolateWorker> _active = <_IsolateWorker>{};
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (var i = 0; i < size; i++) {
      _idle.add(await _IsolateWorker.spawn());
    }
  }

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

      worker
          .run(job)
          .then((value) {
            if (!job.completer.isCompleted) {
              job.completer.complete(TaskExecutionSuccess(value));
            }
          })
          .catchError((error, StackTrace stack) {
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

sealed class TaskExecutionResult {
  const TaskExecutionResult();
}

class TaskExecutionSuccess extends TaskExecutionResult {
  const TaskExecutionSuccess(this.value);

  final Object? value;
}

class TaskExecutionFailure extends TaskExecutionResult {
  const TaskExecutionFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class TaskExecutionTimeout extends TaskExecutionResult {
  const TaskExecutionTimeout({required this.taskName, this.limit});

  final String taskName;
  final Duration? limit;
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

class _RemoteTaskError implements Exception {
  _RemoteTaskError(this.type, this.message, this.stackTrace);

  final String type;
  final String message;
  final String stackTrace;

  @override
  String toString() => '$type: $message\n$stackTrace';
}
