import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_checkpoint.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

/// High-level workflow facade that allows scripts to be authored as a single
/// async function using `step`, `sleep`, and `awaitEvent` helpers.
///
/// In script workflows, the `run` function is the execution plan. Declared
/// checkpoints are optional metadata used for tooling, manifests, and
/// dashboards.
class WorkflowScript<T extends Object?> {
  /// Creates a workflow script definition.
  WorkflowScript({
    required String name,
    required WorkflowScriptBody<T> run,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    PayloadCodec<T>? resultCodec,
  }) : definition = WorkflowDefinition<T>.script(
         name: name,
         run: run,
         checkpoints: checkpoints,
         version: version,
         description: description,
         metadata: metadata,
         resultCodec: resultCodec,
       );

  /// The constructed workflow definition.
  final WorkflowDefinition<T> definition;

  /// Builds a typed [WorkflowRef] using this script's registered workflow name
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

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()` and `Type.fromJson(...)`.
  WorkflowRef<TParams, T> refWithJsonCodec<TParams>({
    required TParams Function(Map<String, Object?> payload) decodeParams,
    String? paramsTypeName,
  }) {
    return definition.refWithJsonCodec<TParams>(
      decodeParams: decodeParams,
      paramsTypeName: paramsTypeName,
    );
  }

  /// Builds a typed [NoArgsWorkflowRef] for scripts without start params.
  NoArgsWorkflowRef<T> ref0() {
    return definition.ref0();
  }

  /// Creates a fluent start builder for scripts without start params.
  WorkflowStartBuilder<(), T> startBuilder() {
    return ref0().startBuilder();
  }

  /// Starts this script directly when it does not accept start params.
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

  /// Starts this script directly and waits for completion.
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

  /// Waits for [runId] using this script's result decoding rules.
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
