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

/// Uniform workflow checkpoint view for dashboard/CLI step drilldowns.
class WorkflowStepView {
  /// Creates an immutable step view.
  const WorkflowStepView({
    required this.runId,
    required this.workflow,
    required this.stepName,
    required this.baseStepName,
    this.iteration,
    required this.position,
    this.completedAt,
    this.value,
  });

  /// Creates a step view from a [WorkflowStepEntry].
  factory WorkflowStepView.fromEntry({
    required String runId,
    required String workflow,
    required WorkflowStepEntry entry,
  }) {
    return WorkflowStepView(
      runId: runId,
      workflow: workflow,
      stepName: entry.name,
      baseStepName: entry.baseName,
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
  final String stepName;

  /// Base step name without iteration suffix.
  final String baseStepName;

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
      'stepName': stepName,
      'baseStepName': baseStepName,
      if (iteration != null) 'iteration': iteration,
      'position': position,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      'value': value,
    };
  }
}

/// Combined run + step drilldown view.
class WorkflowRunDetailView {
  /// Creates an immutable run detail view.
  const WorkflowRunDetailView({required this.run, required this.steps});

  /// Run summary view.
  final WorkflowRunView run;

  /// Persisted step views.
  final List<WorkflowStepView> steps;

  /// Serializes this detail view into JSON.
  Map<String, Object?> toJson() => {
    'run': run.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
  };
}
