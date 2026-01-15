import 'package:stem/src/bootstrap/workflow_app.dart' show StemWorkflowApp;
import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/stem.dart' show StemWorkflowApp;

/// Typed result returned by [StemWorkflowApp.waitForCompletion].
///
/// Provides the decoded workflow result (when available) along with the raw
/// [RunState] so callers can continue inspecting suspension metadata,
/// timestamps, or errors.
class WorkflowResult<T extends Object?> {
  /// Creates a workflow result snapshot.
  const WorkflowResult({
    required this.runId,
    required this.status,
    required this.state,
    this.value,
    this.rawResult,
    this.timedOut = false,
  });

  /// Rehydrates a workflow result from serialized JSON.
  factory WorkflowResult.fromJson(Map<String, Object?> json) {
    return WorkflowResult<T>(
      runId: json['runId']?.toString() ?? '',
      status: _statusFromJson(json['status']),
      state: RunState.fromJson(
        (json['state'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      value: json['value'] as T?,
      rawResult: json['rawResult'],
      timedOut: json['timedOut'] == true,
    );
  }

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

  /// Whether the workflow completed successfully.
  bool get isCompleted => status == WorkflowStatus.completed;

  /// Whether the workflow failed.
  bool get isFailed => status == WorkflowStatus.failed;

  /// Converts this result to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'status': status.name,
      'state': state.toJson(),
      'value': value,
      'rawResult': rawResult,
      'timedOut': timedOut,
    };
  }
}

WorkflowStatus _statusFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return WorkflowStatus.running;
  return WorkflowStatus.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => WorkflowStatus.running,
  );
}
