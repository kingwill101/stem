import 'dart:async';

import 'flow_context.dart';
import 'flow_step.dart';
import 'workflow_script_context.dart';

/// Declarative workflow definition built via [FlowBuilder].
typedef WorkflowScriptBody<T extends Object?> =
    FutureOr<T> Function(WorkflowScriptContext context);

enum WorkflowDefinitionKind { flow, script }

/// Declarative workflow definition built via [FlowBuilder] or a higher-level
/// script facade. The definition captures the ordered steps that the runtime
/// will execute along with optional script metadata used by the facade runner.
class WorkflowDefinition<T extends Object?> {
  WorkflowDefinition._({
    required this.name,
    required WorkflowDefinitionKind kind,
    required List<FlowStep> steps,
    this.scriptBody,
  }) : _kind = kind,
       _steps = steps;

  factory WorkflowDefinition.flow({
    required String name,
    required void Function(FlowBuilder builder) build,
  }) {
    final steps = <FlowStep>[];
    build(FlowBuilder(steps));
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.flow,
      steps: steps,
    );
  }

  factory WorkflowDefinition.script({
    required String name,
    required WorkflowScriptBody<T> run,
  }) {
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.script,
      steps: const [],
      scriptBody: run,
    );
  }

  final String name;
  final WorkflowDefinitionKind _kind;
  final List<FlowStep> _steps;
  final WorkflowScriptBody<T>? scriptBody;

  List<FlowStep> get steps => List.unmodifiable(_steps);

  bool get isScript => _kind == WorkflowDefinitionKind.script;
}

/// Builder used by [Flow] to capture workflow steps in declaration order.
class FlowBuilder {
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
  /// `name#iteration` convention so each execution is tracked separately and the
  /// handler receives the iteration number via [FlowContext.iteration].
  void step(
    String name,
    FutureOr<dynamic> Function(FlowContext context) handler, {
    bool autoVersion = false,
  }) {
    _steps.add(
      FlowStep(name: name, handler: handler, autoVersion: autoVersion),
    );
  }
}
