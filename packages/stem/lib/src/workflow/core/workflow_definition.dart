/// Declarative workflow definitions and builders.
///
/// This library provides the [WorkflowDefinition] class, which is used to
/// describe the structure of a workflow, and builders for creating them
/// in a fluent style.
///
/// ## Workflow Kinds
///
/// Stem supports two primary ways to define workflows:
///
/// 1. **Flow**: A list of discrete `FlowStep`s that execute in order. This is
///    the most common model and is easily visualized.
/// 2. **Script**: A procedural Dart function that uses `context.step` to
///    wrap individual pieces of work. This allows for complex branching
///    logic and loops using standard Dart control flow.
///
/// ## Versioning and Metadata
///
/// Each definition can have a `version`, `description`, and arbitrary
/// `metadata`. The `WorkflowRuntime` uses these to track execution and
/// assist with introspection.
///
/// ## Examples
///
/// ### Flow Workflow
/// ```dart
/// final flow = WorkflowDefinition.flow(
///   name: 'process_order',
///   build: (builder) {
///     builder.step('validate_order');
///     builder.step('charge_customer');
///     builder.step('ship_items');
///   },
/// );
/// ```
///
/// ### Script Workflow
/// ```dart
/// final script = WorkflowDefinition.script(
///   name: 'process_order',
///   body: (context) async {
///     await context.step('validate_order', ...);
///     if (isPremium) {
///       await context.step('apply_discount', ...);
///     }
///     await context.step('charge_customer', ...);
///   },
/// );
/// ```
///
/// See also:
/// - `WorkflowRuntime` for the execution engine.
/// - [FlowStep] for the building blocks of flows.
library;

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
  /// Internal constructor used by builders and script facades.
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

  /// Rehydrates a workflow definition from serialized JSON.
  factory WorkflowDefinition.fromJson(Map<String, Object?> json) {
    final kind = _kindFromJson(json['kind']);
    final stepsJson = (json['steps'] as List?) ?? const [];
    final steps = stepsJson
        .whereType<Map<String, Object?>>()
        .map(FlowStep.fromJson)
        .toList();
    final edgesJson = (json['edges'] as List?) ?? const [];
    final edges = edgesJson
        .whereType<Map<String, Object?>>()
        .map(WorkflowEdge.fromJson)
        .toList();
    if (kind == WorkflowDefinitionKind.script) {
      return WorkflowDefinition._(
        name: json['name']?.toString() ?? '',
        kind: kind,
        steps: const [],
        edges: edges,
        version: json['version']?.toString(),
        description: json['description']?.toString(),
        metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
      );
    }
    return WorkflowDefinition._(
      name: json['name']?.toString() ?? '',
      kind: kind,
      steps: steps,
      edges: edges,
      version: json['version']?.toString(),
      description: json['description']?.toString(),
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
    );
  }

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

  /// Serialize the workflow definition for introspection.
  Map<String, Object?> toJson() {
    final steps = <Map<String, Object?>>[];
    for (var i = 0; i < _steps.length; i += 1) {
      final step = _steps[i].toJson();
      step['position'] = i;
      steps.add(step);
    }
    return {
      'name': name,
      'kind': isScript ? 'script' : 'flow',
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      'steps': steps,
      'edges': _edges.map((edge) => edge.toJson()).toList(),
    };
  }
}

/// Describes a directed edge between workflow steps.
class WorkflowEdge {
  /// Creates a workflow edge from [from] to [to].
  const WorkflowEdge({
    required this.from,
    required this.to,
    this.condition,
  });

  /// Rehydrates an edge from serialized JSON.
  factory WorkflowEdge.fromJson(Map<String, Object?> json) {
    return WorkflowEdge(
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      condition: json['condition']?.toString(),
    );
  }

  /// Originating step identifier.
  final String from;

  /// Destination step identifier.
  final String to;

  /// Optional condition or label for the transition.
  final String? condition;

  /// Serialize edge metadata for workflow introspection.
  Map<String, Object?> toJson() {
    return {
      'from': from,
      'to': to,
      if (condition != null) 'condition': condition,
    };
  }
}

WorkflowDefinitionKind _kindFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return WorkflowDefinitionKind.flow;
  return WorkflowDefinitionKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => WorkflowDefinitionKind.flow,
  );
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
