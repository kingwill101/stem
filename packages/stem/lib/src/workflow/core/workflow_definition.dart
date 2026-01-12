import 'dart:async';

import 'package:stem/src/workflow/core/flow.dart' show Flow;
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';
import 'package:stem/src/workflow/workflow.dart' show Flow;
import 'package:stem/stem.dart' show Flow;

/// Declarative workflow definition built via [FlowBuilder].
typedef WorkflowScriptBody<T extends Object?> =
    FutureOr<T> Function(WorkflowScriptContext context);

/// Identifies whether a workflow is step-based or script-based.
enum WorkflowDefinitionKind {
  /// Workflow composed of discrete flow steps.
  flow,

  /// Workflow executed via a script body.
  script,
}

/// Declarative workflow definition built via [FlowBuilder] or a higher-level
/// script facade. The definition captures the ordered steps that the runtime
/// will execute along with optional script metadata used by the facade runner.
class WorkflowDefinition<T extends Object?> {
  WorkflowDefinition._({
    required this.name,
    required WorkflowDefinitionKind kind,
    required List<FlowStep> steps,
    List<WorkflowEdge> edges = const [],
    this.version,
    this.description,
    Map<String, Object?>? metadata,
    this.scriptBody,
  }) : _kind = kind,
       _steps = steps,
       _edges = edges,
       metadata = metadata == null ? null : Map.unmodifiable(metadata);

  /// Creates a flow-based workflow definition.
  factory WorkflowDefinition.flow({
    required String name,
    required void Function(FlowBuilder builder) build,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) {
    final steps = <FlowStep>[];
    build(FlowBuilder(steps));
    final edges = <WorkflowEdge>[];
    for (var i = 0; i < steps.length - 1; i += 1) {
      edges.add(WorkflowEdge(from: steps[i].name, to: steps[i + 1].name));
    }
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.flow,
      steps: steps,
      edges: edges,
      version: version,
      description: description,
      metadata: metadata,
    );
  }

  /// Creates a script-based workflow definition.
  factory WorkflowDefinition.script({
    required String name,
    required WorkflowScriptBody<T> run,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) {
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.script,
      steps: const [],
      edges: const [],
      version: version,
      description: description,
      metadata: metadata,
      scriptBody: run,
    );
  }

  /// Workflow name used for registration and scheduling.
  final String name;
  final WorkflowDefinitionKind _kind;
  final List<FlowStep> _steps;
  final List<WorkflowEdge> _edges;

  /// Optional version identifier for the workflow definition.
  final String? version;

  /// Optional human-friendly description of the workflow definition.
  final String? description;

  /// Optional metadata associated with this workflow definition.
  final Map<String, Object?>? metadata;

  /// Optional script body when using the script facade.
  final WorkflowScriptBody<T>? scriptBody;

  /// Ordered list of steps for flow-based workflows.
  List<FlowStep> get steps => List.unmodifiable(_steps);

  /// Directed edges describing the workflow graph.
  List<WorkflowEdge> get edges => List.unmodifiable(_edges);

  /// Whether this definition represents a script-based workflow.
  bool get isScript => _kind == WorkflowDefinitionKind.script;
}

/// Describes a directed edge between workflow steps.
class WorkflowEdge {
  /// Creates a workflow edge from [from] to [to].
  const WorkflowEdge({
    required this.from,
    required this.to,
    this.condition,
  });

  /// Originating step identifier.
  final String from;

  /// Destination step identifier.
  final String to;

  /// Optional condition or label for the transition.
  final String? condition;
}

/// Builder used by [Flow] to capture workflow steps in declaration order.
class FlowBuilder {
  /// Creates a builder that appends steps to the provided list.
  FlowBuilder(this._steps);

  final List<FlowStep> _steps;

  /// Adds a step to the workflow.
  ///
  /// [name] must be unique within the flow. The [handler] is replayed from the
  /// beginning whenever the run resumes from a suspension, so it should be
  /// idempotent and leverage [FlowContext] helpers (persisted step results,
  /// resume data) to make forward progress.
  ///
  /// When [autoVersion] is `true`, the runtime stores checkpoints using a
  /// `name#iteration` convention so each execution is tracked separately and
  /// the handler receives the iteration number via [FlowContext.iteration].
  void step(
    String name,
    FutureOr<dynamic> Function(FlowContext context) handler, {
    bool autoVersion = false,
    String? title,
    WorkflowStepKind kind = WorkflowStepKind.task,
    Iterable<String> taskNames = const [],
    Map<String, Object?>? metadata,
  }) {
    _steps.add(
      FlowStep(
        name: name,
        handler: handler,
        autoVersion: autoVersion,
        title: title,
        kind: kind,
        taskNames: taskNames,
        metadata: metadata,
      ),
    );
  }
}
