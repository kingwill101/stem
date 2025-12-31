import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_store.dart' show WorkflowStore;
import 'package:stem/src/workflow/workflow.dart' show WorkflowStore;
import 'package:stem/stem.dart' show WorkflowStore;

/// Snapshot of a workflow run persisted by a [WorkflowStore].
///
/// Implementations are expected to treat instances as immutable and return new
/// copies via [copyWith] when mutating fields.
class RunState {
  /// Creates an immutable snapshot of a workflow run.
  const RunState({
    required this.id,
    required this.workflow,
    required this.status,
    required this.cursor,
    required this.params,
    required this.createdAt,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.updatedAt,
    this.cancellationPolicy,
    this.cancellationData,
  });

  /// Unique run identifier.
  final String id;

  /// Workflow name for this run.
  final String workflow;

  /// Current lifecycle status of the run.
  final WorkflowStatus status;

  /// Cursor pointing to the next step to execute.
  final int cursor;

  /// Parameters supplied at workflow start.
  final Map<String, Object?> params;

  /// Timestamp when the workflow run was created.
  final DateTime createdAt;

  /// Final result payload when the run completes.
  final Object? result;

  /// Topic that the run is currently waiting on, if any.
  final String? waitTopic;

  /// Next scheduled resume timestamp, if any.
  final DateTime? resumeAt;

  /// Last error payload recorded for the run.
  final Map<String, Object?>? lastError;

  /// Suspension metadata stored for the waiting step.
  final Map<String, Object?>? suspensionData;

  /// Timestamp of the most recent state mutation / heartbeat, if any.
  final DateTime? updatedAt;

  /// Cancellation policy that was configured when the run started, if any.
  final WorkflowCancellationPolicy? cancellationPolicy;

  /// Metadata recorded when the run is cancelled (automatic or manual).
  final Map<String, Object?>? cancellationData;

  static const _unset = Object();

  /// Whether the run is in a terminal state.
  bool get isTerminal =>
      status == WorkflowStatus.completed ||
      status == WorkflowStatus.failed ||
      status == WorkflowStatus.cancelled;

  /// Returns a copy of this run state with updated fields.
  RunState copyWith({
    WorkflowStatus? status,
    int? cursor,
    Object? result = _unset,
    Object? waitTopic = _unset,
    Object? resumeAt = _unset,
    Map<String, Object?>? lastError,
    Object? suspensionData = _unset,
    DateTime? updatedAt,
    WorkflowCancellationPolicy? cancellationPolicy,
    Map<String, Object?>? cancellationData,
  }) {
    final resolvedResult = result == _unset ? this.result : result;
    final resolvedWaitTopic = waitTopic == _unset
        ? this.waitTopic
        : waitTopic as String?;
    final resolvedResumeAt = resumeAt == _unset
        ? this.resumeAt
        : resumeAt as DateTime?;
    final resolvedSuspensionData = suspensionData == _unset
        ? this.suspensionData
        : suspensionData as Map<String, Object?>?;
    return RunState(
      id: id,
      workflow: workflow,
      status: status ?? this.status,
      cursor: cursor ?? this.cursor,
      params: params,
      result: resolvedResult,
      waitTopic: resolvedWaitTopic,
      resumeAt: resolvedResumeAt,
      lastError: lastError ?? this.lastError,
      suspensionData: resolvedSuspensionData,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      cancellationData: cancellationData ?? this.cancellationData,
    );
  }
}
