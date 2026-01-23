import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/flow_step.dart';

/// Annotation namespace for workflow metadata.
const workflow = WorkflowAnnotations();

/// Collection of workflow-related annotations.
class WorkflowAnnotations {
  /// Creates the workflow annotation namespace.
  const WorkflowAnnotations({
    this.defn = const WorkflowDefn(),
    this.run = const WorkflowRun(),
    this.step = const WorkflowStep(),
  });

  /// Marks a class as a workflow definition.
  final WorkflowDefn defn;

  /// Marks a method as the workflow run entrypoint.
  final WorkflowRun run;

  /// Marks a method as a workflow step.
  final WorkflowStep step;
}

/// Declares a workflow definition class.
class WorkflowDefn {
  /// Creates a workflow definition annotation.
  const WorkflowDefn({
    this.name,
    this.kind = WorkflowKind.flow,
    this.version,
    this.description,
    this.metadata,
  });

  /// Optional override for the workflow definition name.
  final String? name;

  /// Whether the workflow is a flow or script definition.
  final WorkflowKind kind;

  /// Optional workflow version identifier.
  final String? version;

  /// Optional workflow description.
  final String? description;

  /// Optional metadata attached to the workflow definition.
  final Map<String, Object?>? metadata;
}

/// Marks a workflow class method as the run entrypoint.
class WorkflowRun {
  /// Creates a workflow run annotation.
  const WorkflowRun();
}

/// Marks a workflow class method as a durable step.
class WorkflowStep {
  /// Creates a workflow step annotation.
  const WorkflowStep({
    this.name,
    this.autoVersion = false,
    this.title,
    this.kind = WorkflowStepKind.task,
    this.taskNames = const [],
    this.metadata,
  });

  /// Optional override for the step name.
  final String? name;

  /// Whether the runtime should auto-version the step per iteration.
  final bool autoVersion;

  /// Optional human-friendly title for the step.
  final String? title;

  /// Step kind used for introspection.
  final WorkflowStepKind kind;

  /// Optional task names associated with this step.
  final List<String> taskNames;

  /// Optional metadata attached to the step definition.
  final Map<String, Object?>? metadata;
}

/// Declares a function-backed task definition.
class TaskDefn {
  /// Creates a task definition annotation.
  const TaskDefn({
    this.name,
    this.options = const TaskOptions(),
    this.metadata = const TaskMetadata(),
    this.runInIsolate = true,
  });

  /// Optional override for the task name.
  final String? name;

  /// Default options applied to the task handler.
  final TaskOptions options;

  /// Metadata attached to the task handler.
  final TaskMetadata metadata;

  /// Whether the task should run inside an isolate.
  final bool runInIsolate;
}

/// Workflow definition type for annotated definitions.
enum WorkflowKind {
  /// Flow-based workflow definitions built from ordered steps.
  flow,

  /// Script-based workflow definitions executed via a run body.
  script,
}
