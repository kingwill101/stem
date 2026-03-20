import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

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

  /// Builds a typed [WorkflowRef] backed by a DTO [paramsCodec].
  WorkflowRef<TParams, T> refWithCodec<TParams>({
    required PayloadCodec<TParams> paramsCodec,
  }) {
    return definition.refWithCodec<TParams>(paramsCodec: paramsCodec);
  }

  /// Builds a typed [NoArgsWorkflowRef] for flows without start params.
  NoArgsWorkflowRef<T> ref0() {
    return definition.ref0();
  }

  /// Creates a fluent start builder for flows without start params.
  WorkflowStartBuilder<(), T> startBuilder() {
    return ref0().startBuilder();
  }

  /// Starts this flow directly when it does not accept start params.
  Future<String> startWith(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return ref0().startWith(
      caller,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts this flow directly and waits for completion.
  Future<WorkflowResult<T>?> startAndWaitWith(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return ref0().startAndWaitWith(
      caller,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Waits for [runId] using this flow's result decoding rules.
  Future<WorkflowResult<T>?> waitFor(
    WorkflowCaller caller,
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return ref0().waitFor(
      caller,
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}
