import 'workflow_definition.dart';

/// High-level workflow facade that allows scripts to be authored as a single
/// async function using `step`, `sleep`, and `awaitEvent` helpers.
class WorkflowScript<T extends Object?> {
  WorkflowScript({required String name, required WorkflowScriptBody<T> run})
    : definition = WorkflowDefinition<T>.script(name: name, run: run);

  final WorkflowDefinition<T> definition;
}
