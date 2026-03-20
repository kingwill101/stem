import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_resume_context.dart';

/// Shared execution context surface for flow steps and script checkpoints.
///
/// This keeps the common workflow-authoring capabilities on one type:
/// metadata about the current step/checkpoint, task enqueueing, child-workflow
/// starts, and durable suspension helpers.
abstract interface class WorkflowExecutionContext
    implements TaskEnqueuer, WorkflowCaller, WorkflowResumeContext {
  /// Name of the workflow currently executing.
  String get workflow;

  /// Identifier for the workflow run.
  String get runId;

  /// Name of the current step or checkpoint.
  String get stepName;

  /// Zero-based step or checkpoint index.
  int get stepIndex;

  /// Iteration count for looped steps or checkpoints.
  int get iteration;

  /// Parameters provided when the workflow started.
  Map<String, Object?> get params;

  /// Result of the previous step or checkpoint, if any.
  Object? get previousResult;

  /// Returns a stable idempotency key derived from workflow/run/step state.
  String idempotencyKey([String? scope]);

  /// Optional enqueuer for scheduling tasks with workflow metadata.
  TaskEnqueuer? get enqueuer;

  /// Optional typed workflow caller for spawning child workflows.
  WorkflowCaller? get workflows;
}
