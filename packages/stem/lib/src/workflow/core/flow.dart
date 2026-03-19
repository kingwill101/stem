import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';

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
    PayloadCodec<T>? resultCodec,
  }) : definition = WorkflowDefinition<T>.flow(
         name: name,
         build: build,
         version: version,
         description: description,
         metadata: metadata,
         resultCodec: resultCodec,
       );

  /// The constructed workflow definition.
  final WorkflowDefinition<T> definition;

  /// Builds a typed [WorkflowRef] using this flow's registered workflow name
  /// and result decoder.
  WorkflowRef<TParams, T> ref<TParams>({
    required Map<String, Object?> Function(TParams params) encodeParams,
  }) {
    return definition.ref<TParams>(encodeParams: encodeParams);
  }

  /// Builds a typed [NoArgsWorkflowRef] for flows without start params.
  NoArgsWorkflowRef<T> ref0() {
    return definition.ref0();
  }
}
