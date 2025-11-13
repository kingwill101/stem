import 'workflow_status.dart';
import 'run_state.dart';

/// Typed result returned by [StemWorkflowApp.waitForCompletion].
///
/// Provides the decoded workflow result (when available) along with the raw
/// [RunState] so callers can continue inspecting suspension metadata,
/// timestamps, or errors.
class WorkflowResult<T extends Object?> {
  const WorkflowResult({
    required this.runId,
    required this.status,
    required this.state,
    this.value,
    this.rawResult,
    this.timedOut = false,
  });

  /// Identifier of the workflow run.
  final String runId;

  /// Terminal or current status when the wait completed.
  final WorkflowStatus status;

  /// Snapshot retrieved from the workflow store.
  final RunState state;

  /// Strongly typed value decoded from the persisted workflow result when the
  /// run completed successfully.
  final T? value;

  /// Untyped payload stored by the workflow, useful for legacy consumers or
  /// debugging scenarios.
  final Object? rawResult;

  /// Indicates the wait call returned due to the supplied timeout expiring
  /// before the run reached a terminal state.
  final bool timedOut;

  bool get isCompleted => status == WorkflowStatus.completed;
  bool get isFailed => status == WorkflowStatus.failed;
}
