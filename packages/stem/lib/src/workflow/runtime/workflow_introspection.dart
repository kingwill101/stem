import 'package:stem/src/core/stem_event.dart';

/// Enumerates workflow step event types emitted by the runtime.
enum WorkflowStepEventType {
  /// Step execution started.
  started,

  /// Step execution completed successfully.
  completed,

  /// Step execution failed.
  failed,

  /// Step execution is retrying.
  retrying,
}

/// Runtime-level workflow events emitted by orchestration transitions.
enum WorkflowRuntimeEventType {
  /// A continuation task was enqueued for a run.
  continuationEnqueued,
}

/// Step-level execution event emitted by the workflow runtime.
class WorkflowStepEvent implements StemEvent {
  /// Creates a workflow step execution event.
  WorkflowStepEvent({
    required this.runId,
    required this.workflow,
    required this.stepId,
    required this.type,
    required this.timestamp,
    this.iteration,
    this.result,
    this.error,
    this.metadata,
  });

  /// Workflow run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Step identifier.
  final String stepId;

  /// Event type.
  final WorkflowStepEventType type;

  /// Timestamp when the event was recorded.
  final DateTime timestamp;

  /// Optional step iteration for auto-versioned steps.
  final int? iteration;

  /// Optional result payload for completed steps.
  final Object? result;

  /// Optional error message for failed steps.
  final String? error;

  /// Optional metadata associated with the event.
  final Map<String, Object?>? metadata;

  @override
  String get eventName => 'workflow.step.${type.name}';

  @override
  DateTime get occurredAt => timestamp;

  @override
  Map<String, Object?> get attributes => {
    'runId': runId,
    'workflow': workflow,
    'stepId': stepId,
    if (iteration != null) 'iteration': iteration,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Runtime orchestration event emitted by the workflow runtime.
class WorkflowRuntimeEvent implements StemEvent {
  /// Creates a runtime orchestration event.
  WorkflowRuntimeEvent({
    required this.runId,
    required this.workflow,
    required this.type,
    required this.timestamp,
    this.metadata,
  });

  /// Workflow run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Runtime event type.
  final WorkflowRuntimeEventType type;

  /// Event timestamp.
  final DateTime timestamp;

  /// Additional event metadata.
  final Map<String, Object?>? metadata;

  @override
  String get eventName => 'workflow.runtime.${type.name}';

  @override
  DateTime get occurredAt => timestamp;

  @override
  Map<String, Object?> get attributes => {
    'runId': runId,
    'workflow': workflow,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Sink for workflow step execution events.
mixin WorkflowIntrospectionSink {
  /// Records a workflow step execution [event].
  Future<void> recordStepEvent(WorkflowStepEvent event);

  /// Records a workflow runtime [event]. Optional for sinks that only care
  /// about step-level traces.
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}

/// Default no-op sink for workflow step events.
class NoopWorkflowIntrospectionSink implements WorkflowIntrospectionSink {
  /// Creates a no-op introspection sink.
  const NoopWorkflowIntrospectionSink();

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {}

  @override
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}
