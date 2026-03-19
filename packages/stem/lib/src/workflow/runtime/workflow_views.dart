import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_step_entry.dart';

/// Uniform workflow run view tailored for dashboard/CLI drilldowns.
class WorkflowRunView {
  /// Creates an immutable workflow run view.
  const WorkflowRunView({
    required this.runId,
    required this.workflow,
    required this.status,
    required this.cursor,
    required this.createdAt,
    this.updatedAt,
    this.result,
    this.lastError,
    required this.params,
    required this.runtime,
    this.suspensionData,
  });

  /// Creates a view from a persisted [RunState].
  factory WorkflowRunView.fromState(RunState state) {
    return WorkflowRunView(
      runId: state.id,
      workflow: state.workflow,
      status: state.status,
      cursor: state.cursor,
      createdAt: state.createdAt,
      updatedAt: state.updatedAt,
      result: state.result,
      lastError: state.lastError,
      params: state.workflowParams,
      runtime: state.runtimeMetadata.toJson(),
      suspensionData: state.suspensionData,
    );
  }

  /// Run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Current lifecycle status.
  final WorkflowStatus status;

  /// Current cursor position.
  final int cursor;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// Final result payload when completed.
  final Object? result;

  /// Last error payload, if present.
  final Map<String, Object?>? lastError;

  /// Public user-supplied workflow params.
  final Map<String, Object?> params;

  /// Run-scoped runtime metadata (queues/channel/serialization framing).
  final Map<String, Object?> runtime;

  /// Suspension payload, if run is suspended.
  final Map<String, Object?>? suspensionData;

  /// Serializes this view into JSON.
  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'workflow': workflow,
      'status': status.name,
      'cursor': cursor,
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (result != null) 'result': result,
      if (lastError != null) 'lastError': lastError,
      'params': params,
      'runtime': runtime,
      if (suspensionData != null) 'suspensionData': suspensionData,
    };
  }
}

/// Uniform workflow checkpoint view for dashboard/CLI drilldowns.
class WorkflowCheckpointView {
  /// Creates an immutable checkpoint view.
  const WorkflowCheckpointView({
    required this.runId,
    required this.workflow,
    required this.checkpointName,
    required this.baseCheckpointName,
    this.iteration,
    required this.position,
    this.completedAt,
    this.value,
  });

  /// Creates a checkpoint view from a [WorkflowStepEntry].
  factory WorkflowCheckpointView.fromEntry({
    required String runId,
    required String workflow,
    required WorkflowStepEntry entry,
  }) {
    return WorkflowCheckpointView(
      runId: runId,
      workflow: workflow,
      checkpointName: entry.name,
      baseCheckpointName: entry.baseName,
      iteration: entry.iteration,
      position: entry.position,
      completedAt: entry.completedAt,
      value: entry.value,
    );
  }

  /// Run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Persisted checkpoint name.
  final String checkpointName;

  /// Base step name without iteration suffix.
  final String baseCheckpointName;

  /// Optional iteration suffix.
  final int? iteration;

  /// Zero-based checkpoint order.
  final int position;

  /// Completion timestamp, if available.
  final DateTime? completedAt;

  /// Persisted checkpoint value.
  final Object? value;

  /// Serializes this view into JSON.
  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'workflow': workflow,
      'checkpointName': checkpointName,
      'baseCheckpointName': baseCheckpointName,
      if (iteration != null) 'iteration': iteration,
      'position': position,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      'value': value,
    };
  }
}

/// Combined run + checkpoint drilldown view.
class WorkflowRunDetailView {
  /// Creates an immutable run detail view.
  const WorkflowRunDetailView({required this.run, required this.checkpoints});

  /// Run summary view.
  final WorkflowRunView run;

  /// Persisted checkpoint views.
  final List<WorkflowCheckpointView> checkpoints;

  /// Serializes this detail view into JSON.
  Map<String, Object?> toJson() => {
    'run': run.toJson(),
    'checkpoints': checkpoints.map((step) => step.toJson()).toList(),
  };
}
