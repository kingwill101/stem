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
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    String? resultTypeName,
  }) : definition = WorkflowDefinition<T>.script(
         name: name,
         run: run,
         checkpoints: checkpoints,
         version: version,
         description: description,
         metadata: metadata,
         resultCodec: resultCodec,
         decodeResultJson: decodeResultJson,
         resultTypeName: resultTypeName,
       );

  /// Creates a script definition whose final result uses a custom payload
  /// codec.
  factory WorkflowScript.codec({
    required String name,
    required WorkflowScriptBody<T> run,
    required PayloadCodec<T> resultCodec,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
      version: version,
      description: description,
      metadata: metadata,
      resultCodec: resultCodec,
    );
  }

  /// Creates a script definition whose final result is a DTO-backed JSON
  /// value.
  factory WorkflowScript.json({
    required String name,
    required WorkflowScriptBody<T> run,
    required T Function(Map<String, dynamic> payload) decodeResult,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    String? resultTypeName,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
      version: version,
      description: description,
      metadata: metadata,
      decodeResultJson: decodeResult,
      resultTypeName: resultTypeName,
    );
  }

  /// Creates a script definition whose final result is a versioned DTO-backed
  /// JSON value.
  factory WorkflowScript.versionedJson({
    required String name,
    required WorkflowScriptBody<T> run,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decodeResult,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? workflowVersion,
    String? description,
    Map<String, Object?>? metadata,
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
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

  /// Creates a script definition whose final result uses a reusable version
  /// registry.
  factory WorkflowScript.versionedJsonRegistry({
    required String name,
    required WorkflowScriptBody<T> run,
    required int version,
    required PayloadVersionRegistry<T> resultRegistry,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? workflowVersion,
    String? description,
    Map<String, Object?>? metadata,
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
      version: workflowVersion,
      description: description,
      metadata: metadata,
      resultCodec: PayloadCodec<T>.versionedJsonRegistry(
        version: version,
        registry: resultRegistry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$T',
      ),
    );
  }

  /// Creates a script definition whose final result is a versioned custom map
  /// payload.
  factory WorkflowScript.versionedMap({
    required String name,
    required WorkflowScriptBody<T> run,
    required Object? Function(T value) encodeResult,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decodeResult,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? workflowVersion,
    String? description,
    Map<String, Object?>? metadata,
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
      version: workflowVersion,
      description: description,
      metadata: metadata,
      resultCodec: PayloadCodec<T>.versionedMap(
        encode: encodeResult,
        version: version,
        decode: decodeResult,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$T',
      ),
    );
  }

  /// Creates a script definition whose final result is a versioned custom map
  /// payload decoded through a reusable registry.
  factory WorkflowScript.versionedMapRegistry({
    required String name,
    required WorkflowScriptBody<T> run,
    required Object? Function(T value) encodeResult,
    required int version,
    required PayloadVersionRegistry<T> resultRegistry,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? workflowVersion,
    String? description,
    Map<String, Object?>? metadata,
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return WorkflowScript<T>(
      name: name,
      run: run,
      checkpoints: checkpoints,
      version: workflowVersion,
      description: description,
      metadata: metadata,
      resultCodec: PayloadCodec<T>.versionedMapRegistry(
        encode: encodeResult,
        version: version,
        registry: resultRegistry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$T',
      ),
    );
  }

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
  WorkflowRef<TParams, T> refCodec<TParams>({
    required PayloadCodec<TParams> paramsCodec,
  }) {
    return definition.refCodec<TParams>(paramsCodec: paramsCodec);
  }

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()`.
  WorkflowRef<TParams, T> refJson<TParams>({
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    T Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refJson<TParams>(
      decodeResultJson: decodeResultJson,
      decodeResultVersionedJson: decodeResultVersionedJson,
      defaultDecodeVersion: defaultDecodeVersion,
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

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()` and decode versioned results through a reusable registry.
  WorkflowRef<TParams, T> refVersionedJsonRegistry<TParams>({
    required int version,
    required PayloadVersionRegistry<T> resultRegistry,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refVersionedJsonRegistry<TParams>(
      version: version,
      resultRegistry: resultRegistry,
      defaultDecodeVersion: defaultDecodeVersion,
      paramsTypeName: paramsTypeName,
      resultTypeName: resultTypeName,
    );
  }

  /// Builds a typed [WorkflowRef] for custom map params that persist a schema
  /// [version] beside the payload.
  WorkflowRef<TParams, T> refVersionedMap<TParams>({
    required Object? Function(TParams params) encodeParams,
    required int version,
    T Function(Map<String, dynamic> payload)? decodeResultJson,
    T Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refVersionedMap<TParams>(
      encodeParams: encodeParams,
      version: version,
      decodeResultJson: decodeResultJson,
      decodeResultVersionedJson: decodeResultVersionedJson,
      defaultDecodeVersion: defaultDecodeVersion,
      paramsTypeName: paramsTypeName,
      resultTypeName: resultTypeName,
    );
  }

  /// Builds a typed [WorkflowRef] for custom map params that persist a schema
  /// [version] and decode versioned results through a reusable registry.
  WorkflowRef<TParams, T> refVersionedMapRegistry<TParams>({
    required Object? Function(TParams params) encodeParams,
    required int version,
    required PayloadVersionRegistry<T> resultRegistry,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    return definition.refVersionedMapRegistry<TParams>(
      encodeParams: encodeParams,
      version: version,
      resultRegistry: resultRegistry,
      defaultDecodeVersion: defaultDecodeVersion,
      paramsTypeName: paramsTypeName,
      resultTypeName: resultTypeName,
    );
  }

  /// Builds a typed [NoArgsWorkflowRef] for scripts without start params.
  NoArgsWorkflowRef<T> ref0() {
    return definition.ref0();
  }

  /// Starts this script directly when it does not accept start params.
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

  /// Starts this script directly and waits for completion.
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
