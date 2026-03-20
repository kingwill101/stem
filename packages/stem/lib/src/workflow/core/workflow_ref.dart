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
    TResult Function(Object? payload)? decodeResult,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    final resultCodec = decodeResultJson == null
        ? null
        : PayloadCodec<TResult>.json(
            decode: decodeResultJson,
            typeName: resultTypeName ?? '$TResult',
          );
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
    TResult Function(Object? payload)? decodeResult,
    String? paramsTypeName,
    String? resultTypeName,
  }) {
    final resultCodec = decodeResultJson == null
        ? null
        : PayloadCodec<TResult>.json(
            decode: decodeResultJson,
            typeName: resultTypeName ?? '$TResult',
          );
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

  /// Builds a workflow start call from typed arguments.
  WorkflowStartCall<TParams, TResult> call(
    TParams params, {
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

  /// Creates a fluent builder for this workflow start.
  WorkflowStartBuilder<TParams, TResult> prepareStart(TParams params) {
    return WorkflowStartBuilder(definition: this, params: params);
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
    return call(
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).start(caller);
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
    return call(
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).startAndWait(
      caller,
      pollInterval: pollInterval,
      timeout: timeout,
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

  /// Creates a fluent builder for this workflow start.
  WorkflowStartBuilder<(), TResult> prepareStart() {
    return asRef.prepareStart(());
  }

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

  /// Returns a copy of this call with updated workflow start options.
  WorkflowStartCall<TParams, TResult> copyWith({
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return WorkflowStartCall._(
      definition: definition,
      params: params,
      parentRunId: parentRunId ?? this.parentRunId,
      ttl: ttl ?? this.ttl,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
    );
  }
}

/// Fluent builder used to construct rich workflow start requests.
class WorkflowStartBuilder<TParams, TResult extends Object?> {
  /// Creates a fluent builder for workflow starts.
  WorkflowStartBuilder({required this.definition, required this.params});

  /// Workflow definition used to construct the start call.
  final WorkflowRef<TParams, TResult> definition;

  /// Typed parameters for the workflow invocation.
  final TParams params;

  String? _parentRunId;
  Duration? _ttl;
  WorkflowCancellationPolicy? _cancellationPolicy;

  /// Sets the parent workflow run id for this start.
  WorkflowStartBuilder<TParams, TResult> parentRunId(String parentRunId) {
    _parentRunId = parentRunId;
    return this;
  }

  /// Sets the retention TTL for this run.
  WorkflowStartBuilder<TParams, TResult> ttl(Duration ttl) {
    _ttl = ttl;
    return this;
  }

  /// Sets the cancellation policy for this run.
  WorkflowStartBuilder<TParams, TResult> cancellationPolicy(
    WorkflowCancellationPolicy cancellationPolicy,
  ) {
    _cancellationPolicy = cancellationPolicy;
    return this;
  }

  /// Builds the [WorkflowStartCall] with accumulated overrides.
  WorkflowStartCall<TParams, TResult> build() {
    return definition.call(
      params,
      parentRunId: _parentRunId,
      ttl: _ttl,
      cancellationPolicy: _cancellationPolicy,
    );
  }
}

/// Convenience helpers for dispatching prebuilt [WorkflowStartCall] instances.
extension WorkflowStartCallExtension<TParams, TResult extends Object?>
    on WorkflowStartCall<TParams, TResult> {
  /// Starts this typed workflow call with the provided [caller].
  Future<String> start(WorkflowCaller caller) {
    return caller.startWorkflowCall(this);
  }

  /// Starts this typed workflow call with [caller] and waits for the result.
  Future<WorkflowResult<TResult>?> startAndWait(
    WorkflowCaller caller, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    final runIdFuture = start(caller);
    return runIdFuture.then((runId) {
      return definition.waitFor(
        caller,
        runId,
        pollInterval: pollInterval,
        timeout: timeout,
      );
    });
  }
}

/// Convenience helpers for dispatching [WorkflowStartBuilder] instances.
extension WorkflowStartBuilderExtension<TParams, TResult extends Object?>
    on WorkflowStartBuilder<TParams, TResult> {
  /// Builds this workflow call and starts it with the provided [caller].
  Future<String> start(WorkflowCaller caller) {
    return build().start(caller);
  }

  /// Builds this workflow call, starts it with [caller], and waits for the
  /// result.
  Future<WorkflowResult<TResult>?> startAndWait(
    WorkflowCaller caller, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return build().startAndWait(
      caller,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

/// Caller-bound fluent workflow start builder.
///
/// This mirrors the role `TaskInvocationContext.prepareEnqueue(...)` plays for
/// tasks: a workflow-capable caller can create a fluent start request without
/// pivoting back through the workflow ref for dispatch.
class BoundWorkflowStartBuilder<TParams, TResult extends Object?> {
  /// Creates a caller-bound workflow start builder.
  BoundWorkflowStartBuilder._({
    required WorkflowCaller caller,
    required WorkflowStartBuilder<TParams, TResult> builder,
  }) : _caller = caller,
       _builder = builder;

  final WorkflowCaller _caller;
  final WorkflowStartBuilder<TParams, TResult> _builder;

  /// Sets the parent workflow run id for this start.
  BoundWorkflowStartBuilder<TParams, TResult> parentRunId(String parentRunId) {
    _builder.parentRunId(parentRunId);
    return this;
  }

  /// Sets the retention TTL for this run.
  BoundWorkflowStartBuilder<TParams, TResult> ttl(Duration ttl) {
    _builder.ttl(ttl);
    return this;
  }

  /// Sets the cancellation policy for this run.
  BoundWorkflowStartBuilder<TParams, TResult> cancellationPolicy(
    WorkflowCancellationPolicy cancellationPolicy,
  ) {
    _builder.cancellationPolicy(cancellationPolicy);
    return this;
  }

  /// Builds the [WorkflowStartCall] with accumulated overrides.
  WorkflowStartCall<TParams, TResult> build() => _builder.build();

  /// Starts the built workflow call with the bound caller.
  Future<String> start() => _builder.start(_caller);

  /// Starts the built workflow call with the bound caller and waits for the
  /// typed workflow result.
  Future<WorkflowResult<TResult>?> startAndWait({
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return _builder.startAndWait(
      _caller,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

/// Convenience helpers for building typed workflow starts directly from a
/// workflow-capable caller.
extension WorkflowCallerBuilderExtension on WorkflowCaller {
  /// Creates a caller-bound fluent start builder for a typed workflow ref.
  BoundWorkflowStartBuilder<TParams, TResult>
  prepareStart<TParams, TResult extends Object?>({
    required WorkflowRef<TParams, TResult> definition,
    required TParams params,
  }) {
    return BoundWorkflowStartBuilder._(
      caller: this,
      builder: definition.prepareStart(params),
    );
  }

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
