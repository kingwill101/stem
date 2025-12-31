import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart' show Stem;
import 'package:stem/stem.dart' show Stem;

/// Typed view over a [TaskStatus] returned by helpers such as
/// [Stem.waitForTask] or canvas typed operations.
class TaskResult<T extends Object?> {
  /// Creates a typed task result snapshot.
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

  /// Whether the task completed successfully.
  bool get isSucceeded => status.state == TaskState.succeeded;

  /// Whether the task failed.
  bool get isFailed => status.state == TaskState.failed;

  /// Whether the task was cancelled.
  bool get isCancelled => status.state == TaskState.cancelled;
}
