/// Isolate pool management for concurrent task execution.
///
/// This library provides a managed pool of isolates ([TaskIsolatePool]) that
/// enables concurrent task execution with automatic scaling, recycling, and
/// lifecycle management.
///
/// ## Architecture
///
/// The pool maintains a set of worker isolates that can execute tasks in
/// parallel. When a task is submitted via [TaskIsolatePool.execute], it is
/// either assigned to an idle isolate or queued until one becomes available.
///
/// ## Key Features
///
/// - **Dynamic Scaling**: Resize the pool at runtime with
///   [TaskIsolatePool.resize]
/// - **Automatic Recycling**: Isolates are recycled based on task count or
///   memory
/// - **Timeout Handling**: Hard timeouts terminate stuck tasks
/// - **Control Signals**: Tasks can receive control signals during execution
///
/// ## Recycle Policies
///
/// Isolates can be recycled for several reasons (see [IsolateRecycleReason]):
/// - [IsolateRecycleReason.maxTasks]: Exceeded max tasks per isolate
/// - [IsolateRecycleReason.memory]: Exceeded memory threshold
/// - [IsolateRecycleReason.scaleDown]: Pool is scaling down
/// - [IsolateRecycleReason.shutdown]: Pool is being disposed
///
/// ## Example
///
/// ```dart
/// final pool = TaskIsolatePool(size: 4);
/// await pool.start();
///
/// final result = await pool.execute(
///   myTaskEntrypoint,
///   {'arg': 'value'},
///   {'header': 'value'},
///   {},
///   1, // attempt
///   (signal) => print('Control signal: $signal'),
///   taskName: 'my_task',
///   taskId: 'task-123',
/// );
///
/// if (result is TaskExecutionSuccess) {
///   print('Result: ${result.value}');
/// }
///
/// await pool.dispose();
/// ```
///
/// See also:
/// - [Worker] for the high-level task consumer that uses this pool
/// - [TaskRunRequest] for the message format sent to isolates
library;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/worker/isolate_messages.dart';
import 'package:stem/src/worker/worker.dart';

/// A handler for task control signals.
typedef TaskControlHandler =
    FutureOr<void> Function(TaskInvocationSignal signal);

/// Reason an isolate was recycled or disposed.
enum IsolateRecycleReason {
  /// Recycled due to scaling down the pool.
  scaleDown,

  /// Recycled after reaching the max task limit.
  maxTasks,

  /// Recycled after exceeding memory limits.
  memory,

  /// Recycled during shutdown.
  shutdown,
}

/// Metadata describing an isolate recycle event.
class IsolateRecycleEvent {
  /// Creates a recycle event record.
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
///
/// ## Lifecycle
///
/// 1. Create pool with initial size: `TaskIsolatePool(size: 4)`
/// 2. Start pool to spawn isolates: `await pool.start()`
/// 3. Execute tasks: `await pool.execute(...)`
/// 4. Dispose when done: `await pool.dispose()`
///
/// ## Dynamic Scaling
///
/// The pool can be resized at runtime via [resize]:
///
/// ```dart
/// // Scale up for high load
/// await pool.resize(16);
///
/// // Scale down during quiet periods
/// await pool.resize(2);
/// ```
///
/// ## Recycling Policies
///
/// Configure isolate recycling via [updateRecyclePolicy]:
///
/// ```dart
/// pool.updateRecyclePolicy(
///   maxTasksPerIsolate: 1000,  // Recycle after 1000 tasks
///   maxMemoryBytes: 256 * 1024 * 1024,  // Recycle at 256MB
/// );
/// ```
///
/// ## Callbacks
///
/// - [onSpawned]: Called when an isolate is created
/// - [onRecycle]: Called when an isolate is recycled with reason
/// - [onDisposed]: Called when an isolate is disposed
///
/// ## Example
///
/// ```dart
/// final pool = TaskIsolatePool(
///   size: 4,
///   onRecycle: (event) {
///     print('Recycled: ${event.reason}, tasks: ${event.tasksExecuted}');
///   },
/// );
///
/// await pool.start();
///
/// final result = await pool.execute(
///   myHandler,
///   {'key': 'value'},
///   {},
///   {},
///   1,
///   (signal) => print('Signal: $signal'),
///   taskName: 'my_task',
///   taskId: 'task-123',
/// );
///
/// await pool.dispose();
/// ```
///
/// ## See Also
///
/// - [Worker] for the high-level consumer that uses this pool
/// - [IsolateRecycleReason] for recycling triggers
/// - [TaskExecutionResult] for execution outcomes
class TaskIsolatePool {
  /// Creates a pool with the provided initial [size].
  ///
  /// The pool will spawn [size] isolates when [start] is called.
  /// Size is clamped to a minimum of 1.
  ///
  /// Optional callbacks:
  /// - [onRecycle]: Called when an isolate is recycled
  /// - [onSpawned]: Called after an isolate is spawned
  /// - [onDisposed]: Called after an isolate is disposed
  TaskIsolatePool({
    required int size,
    this.onRecycle,
    this.onSpawned,
    this.onDisposed,
  }) : _targetSize = math.max(1, size);

  /// Callback invoked when an isolate is recycled.
  final void Function(IsolateRecycleEvent event)? onRecycle;

  /// Callback invoked after an isolate is spawned.
  final FutureOr<void> Function(int isolateId)? onSpawned;

  /// Callback invoked after an isolate is disposed.
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
  void updateRecyclePolicy({int? maxTasksPerIsolate, int? maxMemoryBytes}) {
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
    required String taskName,
    required String taskId,
    Duration? hardTimeout,
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
      taskId: taskId,
    );
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  /// The main event loop for the isolate pool.
  ///
  /// This method is responsible for:
  /// 1. Mapping queued [_TaskJob]s to idle isolates.
  /// 2. Spawning new isolates if capacity allows.
  /// 3. Initiating recycling of isolates that have exceeded thresholds.
  /// 4. Cleaning up results from disposed isolates.
  ///
  /// It runs after every state change (submit, result, spawn, dispose).
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

      unawaited(
        entry.worker
            .run(job)
            .then((response) {
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
              } else if (response is TaskRunRetry) {
                job.completer.complete(
                  TaskExecutionRetry(_retryRequestFromResponse(response)),
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
            })
            .catchError((Object error, StackTrace stack) {
              if (!job.completer.isCompleted) {
                job.completer.complete(TaskExecutionFailure(error, stack));
              }
            }),
      );

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

      unawaited(
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
            await _disposeEntry(entry, reason: _determineRecycleReason(entry));
          } else if (_pendingDisposals > 0 && entry.draining) {
            _pendingDisposals -= 1;
            await _disposeEntry(entry, reason: IsolateRecycleReason.scaleDown);
          } else {
            entry.draining = false;
            _idle.add(entry);
          }
          _pump();
        }),
      );
    }
  }

  /// Determines if an isolate should be recycled after completing a task.
  ///
  /// ## Implementation Details
  ///
  /// Checks three conditions in order:
  ///
  /// 1. **Draining flag**: If `entry.draining` is true, the isolate was
  ///    marked for disposal during scale-down and should be recycled.
  ///
  /// 2. **Task count threshold**: If `_maxTasksPerIsolate` is set and
  ///    `entry.tasksExecuted` >= threshold, the isolate has processed
  ///    too many tasks and may have accumulated memory/state drift.
  ///
  /// 3. **Memory threshold**: If `_maxMemoryBytes` is set and
  ///    `entry.lastRssBytes` >= threshold, the isolate is using too
  ///    much memory and should be recycled to reclaim resources.
  ///
  /// ## Returns
  ///
  /// `true` if the isolate should be disposed and replaced.
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

  /// Determines why an isolate should be recycled.
  ///
  /// Inspects the `maxTasks` and `maxMemory` thresholds against the isolate's
  /// actual consumption.
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

  /// Spawns new isolates if the current pool size is below [_targetSize].
  ///
  /// Uses [_IsolateWorker.spawn] to create the underlying isolate and
  /// wraps it in a [_PoolEntry].
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
    required this.taskName,
    required this.taskId,
    this.hardTimeout,
  });

  final TaskEntrypoint entrypoint;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final int attempt;
  final TaskControlHandler onControl;
  final Duration? hardTimeout;
  final String taskName;
  final String taskId;

  final Completer<TaskExecutionResult> completer =
      Completer<TaskExecutionResult>();
}

/// The result of a task execution.
sealed class TaskExecutionResult {
  /// Creates a task execution result.
  const TaskExecutionResult();
}

/// A successful task execution with result [value].
class TaskExecutionSuccess extends TaskExecutionResult {
  /// Creates a successful execution result.
  const TaskExecutionSuccess(this.value, {this.memoryBytes});

  /// The result value of the task.
  final Object? value;

  /// Last reported resident set size for the isolate, in bytes.
  final int? memoryBytes;
}

/// A failed task execution with [error] and [stackTrace].
class TaskExecutionFailure extends TaskExecutionResult {
  /// Creates a failed execution result.
  const TaskExecutionFailure(this.error, this.stackTrace);

  /// The error that occurred.
  final Object error;

  /// The stack trace of the error.
  final StackTrace stackTrace;
}

/// A retry request surfaced from an isolate task.
class TaskExecutionRetry extends TaskExecutionResult {
  /// Creates a retry execution result.
  const TaskExecutionRetry(this.request);

  /// Retry request details.
  final TaskRetryRequest request;
}

/// A timed-out task execution for [taskName] with optional [limit].
class TaskExecutionTimeout extends TaskExecutionResult {
  /// Creates a timeout execution result.
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
      id: job.taskId,
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
      _sendPort.send(const TaskWorkerShutdown());
    } on Object {
      // Ignore send failures if the isolate already exited.
    }
    _isolate.kill(priority: Isolate.immediate);
  }
}

TaskRetryRequest _retryRequestFromResponse(TaskRunRetry response) {
  TaskRetryPolicy? retryPolicy;
  final policy = response.retryPolicy;
  if (policy != null) {
    retryPolicy = TaskRetryPolicy.fromJson(policy);
  }
  return TaskRetryRequest(
    countdown: response.countdownMs != null
        ? Duration(milliseconds: response.countdownMs!)
        : null,
    eta: response.eta != null ? DateTime.tryParse(response.eta!) : null,
    retryPolicy: retryPolicy,
    maxRetries: response.maxRetries,
    timeLimit: response.timeLimitMs != null
        ? Duration(milliseconds: response.timeLimitMs!)
        : null,
    softTimeLimit: response.softTimeLimitMs != null
        ? Duration(milliseconds: response.softTimeLimitMs!)
        : null,
  );
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
