import 'workflow_definition.dart';

/// High-level workflow facade that allows scripts to be authored as a single
/// async function using `step`, `sleep`, and `awaitEvent` helpers.
class WorkflowScript {
  WorkflowScript({required String name, required WorkflowScriptBody run})
    : definition = WorkflowDefinition.script(name: name, run: run);

  final WorkflowDefinition definition;
}
