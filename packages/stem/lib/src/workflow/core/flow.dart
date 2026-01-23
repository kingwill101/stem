import 'package:stem/src/workflow/core/workflow_definition.dart';

/// Convenience wrapper that builds a [WorkflowDefinition] using the declarative
/// [FlowBuilder] DSL.
///
/// A `Flow` is typically registered with `StemWorkflowApp` to make it available
/// for scheduling via `startWorkflow`. Specify [T] to document the result type
/// produced by the workflow; it defaults to [Object] for backwards
/// compatibility.
class Flow<T extends Object?> {
  /// Creates a flow definition using the [FlowBuilder] DSL.
  Flow({
    required String name,
    required void Function(FlowBuilder builder) build,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) : definition = WorkflowDefinition<T>.flow(
         name: name,
         build: build,
         version: version,
         description: description,
         metadata: metadata,
       );

  /// The constructed workflow definition.
  final WorkflowDefinition<T> definition;
}
