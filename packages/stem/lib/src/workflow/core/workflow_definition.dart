import 'dart:async';

import 'flow_context.dart';
import 'flow_step.dart';

/// Declarative workflow definition built via [FlowBuilder].
class WorkflowDefinition {
  WorkflowDefinition({
    required this.name,
    required void Function(FlowBuilder builder) build,
  }) {
    build(FlowBuilder(_steps));
  }

  final String name;
  final List<FlowStep> _steps = [];

  List<FlowStep> get steps => List.unmodifiable(_steps);
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
