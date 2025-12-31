import 'dart:async';
import 'dart:isolate';

/// Signature for task entrypoints that can run inside isolate executors.
typedef TaskEntrypoint =
    FutureOr<Object?> Function(
      TaskInvocationContext context,
      Map<String, Object?> args,
    );

/// Control messages emitted by task entrypoints running inside isolates.
sealed class TaskInvocationSignal {
  const TaskInvocationSignal();
}

/// Signals a heartbeat from an executing task.
class HeartbeatSignal extends TaskInvocationSignal {
  /// Creates a heartbeat signal.
  const HeartbeatSignal();
}

/// Signals a request to extend a task lease.
class ExtendLeaseSignal extends TaskInvocationSignal {
  /// Creates a lease extension signal.
  const ExtendLeaseSignal(this.by);

  /// Duration to extend the lease by.
  final Duration by;
}

/// Signals a task progress update.
class ProgressSignal extends TaskInvocationSignal {
  /// Creates a progress signal with optional metadata.
  const ProgressSignal(this.percentComplete, {this.data});

  /// Completion percentage (0-100).
  final double percentComplete;

  /// Optional progress metadata.
  final Map<String, Object?>? data;
}

/// Context exposed to task entrypoints regardless of execution environment.
class TaskInvocationContext {
  /// Context implementation used when executing locally in the same isolate.
  factory TaskInvocationContext.local({
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(
      double percent, {
      Map<String, Object?>? data,
    })
    progress,
  }) => TaskInvocationContext._(
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: heartbeat,
    extendLease: extendLease,
    progress: progress,
  );

  /// Context implementation used when executing inside a worker isolate.
  factory TaskInvocationContext.remote({
    required SendPort controlPort,
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
  }) => TaskInvocationContext._(
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: () => controlPort.send(const HeartbeatSignal()),
    extendLease: (by) async => controlPort.send(ExtendLeaseSignal(by)),
    progress: (percent, {data}) async =>
        controlPort.send(ProgressSignal(percent, data: data)),
  );
  TaskInvocationContext._({
    required this.headers,
    required this.meta,
    required this.attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(
      double percent, {
      Map<String, Object?>? data,
    })
    progress,
  }) : _heartbeat = heartbeat,
       _extendLease = extendLease,
       _progress = progress;

  /// Headers passed to the task invocation.
  final Map<String, String> headers;

  /// Invocation metadata (e.g. trace, tenant).
  final Map<String, Object?> meta;

  /// Current attempt count.
  final int attempt;

  final void Function() _heartbeat;
  final Future<void> Function(Duration) _extendLease;
  final Future<void> Function(
    double percent, {
    Map<String, Object?>? data,
  })
  _progress;

  /// Notify the worker that the task is still running.
  void heartbeat() => _heartbeat();

  /// Request an extension of the underlying broker lease/visibility timeout.
  Future<void> extendLease(Duration by) => _extendLease(by);

  /// Report progress back to the worker.
  Future<void> progress(double percentComplete, {Map<String, Object?>? data}) =>
      _progress(percentComplete, data: data);
}
