import 'dart:async';
import 'dart:isolate';

/// Signature for task entrypoints that can run inside isolate executors.
typedef TaskEntrypoint = FutureOr<Object?> Function(
  TaskInvocationContext context,
  Map<String, Object?> args,
);

/// Control messages emitted by task entrypoints running inside isolates.
sealed class TaskInvocationSignal {
  const TaskInvocationSignal();
}

class HeartbeatSignal extends TaskInvocationSignal {
  const HeartbeatSignal();
}

class ExtendLeaseSignal extends TaskInvocationSignal {
  const ExtendLeaseSignal(this.by);

  final Duration by;
}

class ProgressSignal extends TaskInvocationSignal {
  const ProgressSignal(this.percentComplete, {this.data});

  final double percentComplete;
  final Map<String, Object?>? data;
}

/// Context exposed to task entrypoints regardless of execution environment.
class TaskInvocationContext {
  TaskInvocationContext._({
    required this.headers,
    required this.meta,
    required this.attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(double percent, {Map<String, Object?>? data})
        progress,
  })  : _heartbeat = heartbeat,
        _extendLease = extendLease,
        _progress = progress;

  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final int attempt;

  final void Function() _heartbeat;
  final Future<void> Function(Duration) _extendLease;
  final Future<void> Function(double percent, {Map<String, Object?>? data})
      _progress;

  /// Notify the worker that the task is still running.
  void heartbeat() => _heartbeat();

  /// Request an extension of the underlying broker lease/visibility timeout.
  Future<void> extendLease(Duration by) => _extendLease(by);

  /// Report progress back to the worker.
  Future<void> progress(double percentComplete, {Map<String, Object?>? data}) =>
      _progress(percentComplete, data: data);

  /// Context implementation used when executing locally in the same isolate.
  factory TaskInvocationContext.local({
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(double percent, {Map<String, Object?>? data})
        progress,
  }) =>
      TaskInvocationContext._(
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
  }) =>
      TaskInvocationContext._(
        headers: headers,
        meta: meta,
        attempt: attempt,
        heartbeat: () => controlPort.send(const HeartbeatSignal()),
        extendLease: (by) async => controlPort.send(ExtendLeaseSignal(by)),
        progress: (percent, {data}) async =>
            controlPort.send(ProgressSignal(percent, data: data)),
      );
}
