import 'contracts.dart';

/// Typed view over a [TaskStatus] returned by helpers such as
/// [Stem.waitForTask] or canvas typed operations.
class TaskResult<T extends Object?> {
  const TaskResult({
    required this.taskId,
    required this.status,
    this.value,
    this.rawPayload,
    this.timedOut = false,
  });

  /// Logical task identifier.
  final String taskId;

  /// Latest status snapshot from the backend.
  final TaskStatus status;

  /// Decoded payload when the task succeeded.
  final T? value;

  /// Raw payload stored by the backend (useful for debugging or manual casts).
  final Object? rawPayload;

  /// Indicates the helper returned because the timeout elapsed before the task
  /// reached a terminal state.
  final bool timedOut;

  bool get isSucceeded => status.state == TaskState.succeeded;
  bool get isFailed => status.state == TaskState.failed;
  bool get isCancelled => status.state == TaskState.cancelled;
}
