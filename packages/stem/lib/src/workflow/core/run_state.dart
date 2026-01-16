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
    this.ownerId,
    this.leaseExpiresAt,
    this.cancellationPolicy,
    this.cancellationData,
  });

  /// Rehydrates a run state from serialized JSON.
  factory RunState.fromJson(Map<String, Object?> json) {
    return RunState(
      id: json['id']?.toString() ?? '',
      workflow: json['workflow']?.toString() ?? '',
      status: _statusFromJson(json['status']),
      cursor: _intFromJson(json['cursor']),
      params: (json['params'] as Map?)?.cast<String, Object?>() ?? const {},
      createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now().toUtc(),
      result: json['result'],
      waitTopic: json['waitTopic'] as String?,
      resumeAt: _dateFromJson(json['resumeAt']),
      lastError: (json['lastError'] as Map?)?.cast<String, Object?>(),
      suspensionData: (json['suspensionData'] as Map?)?.cast<String, Object?>(),
      updatedAt: _dateFromJson(json['updatedAt']),
      ownerId: json['ownerId']?.toString(),
      leaseExpiresAt: _dateFromJson(json['leaseExpiresAt']),
      cancellationPolicy: WorkflowCancellationPolicy.fromJson(
        json['cancellationPolicy'],
      ),
      cancellationData: (json['cancellationData'] as Map?)
          ?.cast<String, Object?>(),
    );
  }

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

  /// Identifier of the worker/runtime currently leasing this run, if any.
  final String? ownerId;

  /// Timestamp when the current lease expires, if any.
  final DateTime? leaseExpiresAt;

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
    Object? ownerId = _unset,
    Object? leaseExpiresAt = _unset,
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
    final resolvedOwnerId = ownerId == _unset
        ? this.ownerId
        : ownerId as String?;
    final resolvedLeaseExpiresAt = leaseExpiresAt == _unset
        ? this.leaseExpiresAt
        : leaseExpiresAt as DateTime?;
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
      ownerId: resolvedOwnerId,
      leaseExpiresAt: resolvedLeaseExpiresAt,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      cancellationData: cancellationData ?? this.cancellationData,
    );
  }

  /// Converts this run state into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'workflow': workflow,
      'status': status.name,
      'cursor': cursor,
      'params': params,
      'createdAt': createdAt.toIso8601String(),
      'result': result,
      'waitTopic': waitTopic,
      'resumeAt': resumeAt?.toIso8601String(),
      'lastError': lastError,
      'suspensionData': suspensionData,
      'updatedAt': updatedAt?.toIso8601String(),
      'ownerId': ownerId,
      'leaseExpiresAt': leaseExpiresAt?.toIso8601String(),
      'cancellationPolicy': cancellationPolicy?.toJson(),
      'cancellationData': cancellationData,
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

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateFromJson(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
