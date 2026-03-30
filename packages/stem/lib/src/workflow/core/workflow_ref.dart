import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

/// Typed producer-facing reference to a registered workflow.
///
/// This mirrors the role `TaskDefinition` plays for tasks: it centralizes the
/// workflow name plus parameter/result encoding rules so producer code can work
/// with one typed handle instead of raw workflow-name strings.
class WorkflowRef<TParams, TResult extends Object?> {
  /// Creates a typed workflow reference.
  const WorkflowRef({
    required this.name,
    required this.encodeParams,
    this.decodeResult,
  });

  /// Creates a typed workflow reference backed by payload codecs.
  factory WorkflowRef.codec({
    required String name,
    required PayloadCodec<TParams> paramsCodec,
    PayloadCodec<TResult>? resultCodec,
    TResult Function(Object? payload)? decodeResult,
  }) {
    return WorkflowRef<TParams, TResult>(
      name: name,
      encodeParams: (params) => _encodeCodecParams(name, paramsCodec, params),
      decodeResult: decodeResult ?? resultCodec?.decode,
    );
  }

  /// Creates a typed workflow reference for DTO params that already expose
  /// `toJson()`.
  factory WorkflowRef.json({
    required String name,
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    TResult Function(Object? payload)? decodeResult,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: defaultDecodeVersion ?? 1,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return WorkflowRef<TParams, TResult>(
      name: name,
      encodeParams: (params) =>
          _encodeJsonParams(params, paramsTypeName ?? '$TParams'),
      decodeResult: decodeResult ?? resultCodec?.decode,
    );
  }

  /// Creates a typed workflow reference for DTO params that already expose
  /// `toJson()` and persist a schema [version] beside the payload.
  factory WorkflowRef.versionedJson({
    required String name,
    required int version,
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    TResult Function(Object? payload)? decodeResult,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: version,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return WorkflowRef<TParams, TResult>(
      name: name,
      encodeParams: (params) => _encodeVersionedJsonParams(
        params,
        version: version,
        typeName: paramsTypeName ?? '$TParams',
      ),
      decodeResult: decodeResult ?? resultCodec?.decode,
    );
  }

  /// Creates a typed workflow reference for DTO params that already expose
  /// `toJson()` and decode versioned results through a reusable registry.
  factory WorkflowRef.versionedJsonRegistry({
    required String name,
    required int version,
    required PayloadVersionRegistry<TResult> resultRegistry,
    TResult Function(Object? payload)? decodeResult,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    final resultCodec = PayloadCodec<TResult>.versionedJsonRegistry(
      version: version,
      registry: resultRegistry,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: resultTypeName ?? '$TResult',
    );
    return WorkflowRef<TParams, TResult>(
      name: name,
      encodeParams: (params) => _encodeVersionedJsonParams(
        params,
        version: version,
        typeName: paramsTypeName ?? '$TParams',
      ),
      decodeResult: decodeResult ?? resultCodec.decode,
    );
  }

  /// Creates a typed workflow reference for custom map params that persist a
  /// schema [version] beside the payload.
  factory WorkflowRef.versionedMap({
    required String name,
    required Object? Function(TParams params) encodeParams,
    required int version,
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    TResult Function(Object? payload)? decodeResult,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    final paramsCodec = PayloadCodec<TParams>.versionedMap(
      encode: encodeParams,
      version: version,
      decode: (payload, _) => throw UnsupportedError(
        'WorkflowRef.versionedMap($name) only uses the params codec for '
        'encoding. Decoding is not supported at the ref layer.',
      ),
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: paramsTypeName ?? '$TParams',
    );
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: version,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return WorkflowRef<TParams, TResult>.codec(
      name: name,
      paramsCodec: paramsCodec,
      resultCodec: resultCodec,
      decodeResult: decodeResult,
    );
  }

  /// Creates a typed workflow reference for custom map params that persist a
  /// schema [version] and decode versioned results through a reusable
  /// registry.
  factory WorkflowRef.versionedMapRegistry({
    required String name,
    required Object? Function(TParams params) encodeParams,
    required int version,
    required PayloadVersionRegistry<TResult> resultRegistry,
    TResult Function(Object? payload)? decodeResult,
    int? defaultDecodeVersion,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    final paramsCodec = PayloadCodec<TParams>.versionedMap(
      encode: encodeParams,
      version: version,
      decode: (payload, _) => throw UnsupportedError(
        'WorkflowRef.versionedMapRegistry($name) only uses the params codec '
        'for encoding. Decoding is not supported at the ref layer.',
      ),
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: paramsTypeName ?? '$TParams',
    );
    final resultCodec = PayloadCodec<TResult>.versionedJsonRegistry(
      version: version,
      registry: resultRegistry,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: resultTypeName ?? '$TResult',
    );
    return WorkflowRef<TParams, TResult>.codec(
      name: name,
      paramsCodec: paramsCodec,
      resultCodec: resultCodec,
      decodeResult: decodeResult,
    );
  }

  /// Registered workflow name.
  final String name;

  /// Encodes typed workflow parameters into the persisted parameter map.
  final Map<String, Object?> Function(TParams params) encodeParams;

  /// Optional decoder for the final workflow result payload.
  final TResult Function(Object? payload)? decodeResult;

  static Map<String, Object?> _encodeCodecParams<T>(
    String workflowName,
    PayloadCodec<T> codec,
    T params,
  ) {
    final payload = codec.encode(params);
    if (payload is Map<String, Object?>) {
      return Map<String, Object?>.from(payload);
    }
    if (payload is Map) {
      final normalized = <String, Object?>{};
      for (final entry in payload.entries) {
        final key = entry.key;
        if (key is! String) {
          throw StateError(
            'WorkflowRef.codec($workflowName) requires payload '
            'keys to be strings, got ${key.runtimeType}.',
          );
        }
        normalized[key] = entry.value;
      }
      return normalized;
    }
    throw StateError(
      'WorkflowRef.codec($workflowName) must encode params to '
      'Map<String, Object?>, got ${payload.runtimeType}.',
    );
  }

  static Map<String, Object?> _encodeJsonParams<T>(T params, String typeName) {
    final payload = PayloadCodec.encodeJsonMap(
      params,
      typeName: typeName,
    );
    return Map<String, Object?>.from(payload);
  }

  static Map<String, Object?> _encodeVersionedJsonParams<T>(
    T params, {
    required int version,
    required String typeName,
  }) {
    final payload = PayloadCodec.encodeVersionedJsonMap(
      params,
      version: version,
      typeName: typeName,
    );
    return Map<String, Object?>.from(payload);
  }

  /// Decodes a final workflow result payload.
  TResult decode(Object? payload) {
    if (payload == null) {
      return null as TResult;
    }
    final decoder = decodeResult;
    if (decoder != null) {
      return decoder(payload);
    }
    return payload as TResult;
  }

  /// Starts this workflow ref directly with [caller] using named args.
  Future<String> start(
    WorkflowCaller caller, {
    required TParams params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return caller.startWorkflowCall(
      buildStart(
        params: params,
        parentRunId: parentRunId,
        ttl: ttl,
        cancellationPolicy: cancellationPolicy,
      ),
    );
  }

  /// Starts this workflow ref with [caller] and waits for the result using
  /// named args.
  Future<WorkflowResult<TResult>?> startAndWait(
    WorkflowCaller caller, {
    required TParams params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    final call = buildStart(
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
    return caller.startWorkflowCall(call).then((runId) {
      return call.definition.waitFor(
        caller,
        runId,
        pollInterval: pollInterval,
        timeout: timeout,
      );
    });
  }

  /// Builds an explicit [WorkflowStartCall] for this workflow ref.
  WorkflowStartCall<TParams, TResult> buildStart({
    required TParams params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return WorkflowStartCall._(
      definition: this,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }
}

/// Typed producer-facing reference for workflows that take no input params.
class NoArgsWorkflowRef<TResult extends Object?> {
  /// Creates a typed workflow reference for workflows without input params.
  const NoArgsWorkflowRef({required this.name, this.decodeResult});

  /// Registered workflow name.
  final String name;

  /// Optional decoder for the final workflow result payload.
  final TResult Function(Object? payload)? decodeResult;

  WorkflowRef<(), TResult> get _inner => WorkflowRef<(), TResult>(
    name: name,
    encodeParams: _encodeParams,
    decodeResult: decodeResult,
  );

  /// Returns the underlying typed workflow ref used for waiting and dispatch.
  WorkflowRef<(), TResult> get asRef => _inner;

  static Map<String, Object?> _encodeParams(() _) => const <String, Object?>{};

  /// Starts this workflow ref directly with [caller].
  Future<String> start(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return asRef.start(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
      caller,
      params: (),
    );
  }

  /// Starts this workflow ref with [caller] and waits for the result.
  Future<WorkflowResult<TResult>?> startAndWait(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return asRef.startAndWait(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
      caller,
      params: (),
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Decodes a final workflow result payload.
  TResult decode(Object? payload) => asRef.decode(payload);

  /// Waits for [runId] using this workflow reference's decode rules.
  Future<WorkflowResult<TResult>?> waitFor(
    WorkflowCaller caller,
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return asRef.waitFor(
      caller,
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

/// Shared typed workflow-start surface used by apps, runtimes, and contexts.
abstract interface class WorkflowCaller {
  /// Starts a workflow from a typed [WorkflowRef].
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  });

  /// Starts a workflow from a prebuilt [WorkflowStartCall].
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  );

  /// Waits for [runId] using the decoding rules from a [WorkflowRef].
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  });
}

/// Typed start request built from a [WorkflowRef].
class WorkflowStartCall<TParams, TResult extends Object?> {
  const WorkflowStartCall._({
    required this.definition,
    required this.params,
    this.parentRunId,
    this.ttl,
    this.cancellationPolicy,
  });

  /// Reference used to build this start call.
  final WorkflowRef<TParams, TResult> definition;

  /// Typed workflow parameters.
  final TParams params;

  /// Optional parent workflow run.
  final String? parentRunId;

  /// Optional run TTL.
  final Duration? ttl;

  /// Optional cancellation policy.
  final WorkflowCancellationPolicy? cancellationPolicy;

  /// Workflow name derived from [definition].
  String get name => definition.name;

  /// Encodes typed parameters into the workflow parameter map.
  Map<String, Object?> encodeParams() => definition.encodeParams(params);
}

/// Convenience helpers for waiting on typed workflow refs using a generic
/// [WorkflowCaller].
extension WorkflowRefExtension<TParams, TResult extends Object?>
    on WorkflowRef<TParams, TResult> {
  /// Waits for [runId] using this workflow reference's decode rules.
  Future<WorkflowResult<TResult>?> waitFor(
    WorkflowCaller caller,
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return caller.waitForWorkflowRef(
      runId,
      this,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}
