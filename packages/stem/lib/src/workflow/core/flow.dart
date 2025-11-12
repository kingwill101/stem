import 'workflow_definition.dart';

/// Convenience wrapper that builds a [WorkflowDefinition] using the declarative
/// [FlowBuilder] DSL.
///
/// A `Flow` is typically registered with `StemWorkflowApp` to make it available
/// for scheduling via `startWorkflow`.
class Flow {
  Flow({
    required String name,
    required void Function(FlowBuilder builder) build,
  }) : definition = WorkflowDefinition.flow(name: name, build: build);

  final WorkflowDefinition definition;
}
