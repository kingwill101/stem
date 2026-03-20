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
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    String? resultTypeName,
  }) : definition = WorkflowDefinition<T>.flow(
         name: name,
         build: build,
         version: version,
         description: description,
         metadata: metadata,
         resultCodec: resultCodec,
         decodeResultJson: decodeResultJson,
         resultTypeName: resultTypeName,
       );

  /// Creates a flow definition whose final result uses a custom payload codec.
  factory Flow.codec({
    required String name,
    required void Function(FlowBuilder builder) build,
    required PayloadCodec<T> resultCodec,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) {
    return Flow<T>(
      name: name,
      build: build,
      version: version,
      description: description,
      metadata: metadata,
      resultCodec: resultCodec,
    );
  }

  /// Creates a flow definition whose final result is a DTO-backed JSON value.
  factory Flow.json({
    required String name,
    required void Function(FlowBuilder builder) build,
    required T Function(Map<String, dynamic> payload) decodeResult,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    String? resultTypeName,
  }) {
    return Flow<T>(
      name: name,
      build: build,
      version: version,
      description: description,
      metadata: metadata,
      decodeResultJson: decodeResult,
      resultTypeName: resultTypeName,
    );
  }

  /// Creates a flow definition whose final result is a versioned DTO-backed
  /// JSON value.
  factory Flow.versionedJson({
    required String name,
    required void Function(FlowBuilder builder) build,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decodeResult,
    String? workflowVersion,
    String? description,
    Map<String, Object?>? metadata,
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return Flow<T>(
      name: name,
      build: build,
      version: workflowVersion,
      description: description,
      metadata: metadata,
      resultCodec: PayloadCodec<T>.versionedJson(
        version: version,
        decode: decodeResult,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$T',
      ),
    );
  }

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
  WorkflowRef<TParams, T> refCodec<TParams>({
    required PayloadCodec<TParams> paramsCodec,
  }) {
    return definition.refCodec<TParams>(paramsCodec: paramsCodec);
  }

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()`.
  WorkflowRef<TParams, T> refJson<TParams>({
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refJson<TParams>(
      decodeResultJson: decodeResultJson,
      paramsTypeName: paramsTypeName,
      resultTypeName: resultTypeName,
    );
  }

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()` and persist a schema [version] beside the payload.
  WorkflowRef<TParams, T> refVersionedJson<TParams>({
    required int version,
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    T Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refVersionedJson<TParams>(
      version: version,
      decodeResultJson: decodeResultJson,
      decodeResultVersionedJson: decodeResultVersionedJson,
      defaultDecodeVersion: defaultDecodeVersion,
      paramsTypeName: paramsTypeName,
      resultTypeName: resultTypeName,
    );
  }

  /// Builds a typed [NoArgsWorkflowRef] for flows without start params.
  NoArgsWorkflowRef<T> ref0() {
    return definition.ref0();
  }

  /// Starts this flow directly when it does not accept start params.
  Future<String> start(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return ref0().start(
      caller,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts this flow directly and waits for completion.
  Future<WorkflowResult<T>?> startAndWait(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return ref0().startAndWait(
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
