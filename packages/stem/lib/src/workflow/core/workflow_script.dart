import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/flow_step.dart';

/// High-level workflow facade that allows scripts to be authored as a single
/// async function using `step`, `sleep`, and `awaitEvent` helpers.
class WorkflowScript<T extends Object?> {
  /// Creates a workflow script definition.
  WorkflowScript({
    required String name,
    required WorkflowScriptBody<T> run,
    Iterable<FlowStep> steps = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) : definition = WorkflowDefinition<T>.script(
         name: name,
         run: run,
         steps: steps,
         version: version,
         description: description,
         metadata: metadata,
       );

  /// The constructed workflow definition.
  final WorkflowDefinition<T> definition;
}
