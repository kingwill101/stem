import 'workflow_status.dart';

/// Snapshot of a workflow run persisted by a [WorkflowStore].
///
/// Implementations are expected to treat instances as immutable and return new
/// copies via [copyWith] when mutating fields.
class RunState {
  const RunState({
    required this.id,
    required this.workflow,
    required this.status,
    required this.cursor,
    required this.params,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
  });

  final String id;
  final String workflow;
  final WorkflowStatus status;
  final int cursor;
  final Map<String, Object?> params;
  final Object? result;
  final String? waitTopic;
  final DateTime? resumeAt;
  final Map<String, Object?>? lastError;
  final Map<String, Object?>? suspensionData;

  static const _unset = Object();

  bool get isTerminal =>
      status == WorkflowStatus.completed ||
      status == WorkflowStatus.failed ||
      status == WorkflowStatus.cancelled;

  RunState copyWith({
    WorkflowStatus? status,
    int? cursor,
    Object? result = _unset,
    Object? waitTopic = _unset,
    Object? resumeAt = _unset,
    Map<String, Object?>? lastError,
    Object? suspensionData = _unset,
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
    );
  }
}
