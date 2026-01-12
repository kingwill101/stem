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

/// Step-level execution event emitted by the workflow runtime.
class WorkflowStepEvent {
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
}

/// Sink for workflow step execution events.
abstract class WorkflowIntrospectionSink {
  /// Records a workflow step execution [event].
  Future<void> recordStepEvent(WorkflowStepEvent event);
}

/// Default no-op sink for workflow step events.
class NoopWorkflowIntrospectionSink implements WorkflowIntrospectionSink {
  /// Creates a no-op introspection sink.
  const NoopWorkflowIntrospectionSink();

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {}
}
