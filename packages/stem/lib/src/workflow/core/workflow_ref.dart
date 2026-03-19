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

  /// Registered workflow name.
  final String name;

  /// Encodes typed workflow parameters into the persisted parameter map.
  final Map<String, Object?> Function(TParams params) encodeParams;

  /// Optional decoder for the final workflow result payload.
  final TResult Function(Object? payload)? decodeResult;

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

  /// Builds a workflow start call without requiring an explicit empty payload.
  WorkflowStartCall<(), TResult> call({
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return asRef.call(
      (),
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts this workflow ref directly with [caller].
  Future<String> startWith(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return call(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).startWith(caller);
  }

  /// Starts this workflow ref directly with a workflow child-caller [context].
  Future<String> startWithContext(
    WorkflowChildCallerContext context, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return call(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).startWithContext(context);
  }

  /// Starts this workflow ref with [caller] and waits for the result.
  Future<WorkflowResult<TResult>?> startAndWaitWith(
    WorkflowCaller caller, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return call(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).startAndWaitWith(
      caller,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Starts this workflow ref with a workflow child-caller [context] and waits
  /// for the result.
  Future<WorkflowResult<TResult>?> startAndWaitWithContext(
    WorkflowChildCallerContext context, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return call(
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    ).startAndWaitWithContext(
      context,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Decodes a final workflow result payload.
  TResult decode(Object? payload) => asRef.decode(payload);

  /// Waits for [runId] using this workflow reference's decode rules.
  Future<WorkflowResult<TResult>?> waitForWith(
    WorkflowCaller caller,
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return asRef.waitForWith(
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

/// Shared contract for contexts that can spawn child workflows.
abstract interface class WorkflowChildCallerContext {
  /// Optional typed workflow caller for spawning child workflows.
  WorkflowCaller? get workflows;
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

/// Convenience helpers for dispatching prebuilt [WorkflowStartCall] instances.
extension WorkflowStartCallExtension<TParams, TResult extends Object?>
    on WorkflowStartCall<TParams, TResult> {
  /// Starts this typed workflow call with the provided [caller].
  Future<String> startWith(WorkflowCaller caller) {
    return caller.startWorkflowCall(this);
  }

  /// Starts this typed workflow call with a workflow child-caller [context].
  Future<String> startWithContext(WorkflowChildCallerContext context) {
    final caller = context.workflows;
    if (caller == null) {
      throw StateError(
        'This workflow context does not support starting child workflows.',
      );
    }
    return startWith(caller);
  }

  /// Starts this typed workflow call with [caller] and waits for the result.
  Future<WorkflowResult<TResult>?> startAndWaitWith(
    WorkflowCaller caller, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    final runId = await startWith(caller);
    return definition.waitForWith(
      caller,
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Starts this typed workflow call with a workflow child-caller [context]
  /// and waits for the result.
  Future<WorkflowResult<TResult>?> startAndWaitWithContext(
    WorkflowChildCallerContext context, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    final caller = context.workflows;
    if (caller == null) {
      throw StateError(
        'This workflow context does not support starting child workflows.',
      );
    }
    return startAndWaitWith(
      caller,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

/// Convenience helpers for waiting on typed workflow refs using a generic
/// [WorkflowCaller].
extension WorkflowRefExtension<TParams, TResult extends Object?>
    on WorkflowRef<TParams, TResult> {
  /// Waits for [runId] using this workflow reference's decode rules.
  Future<WorkflowResult<TResult>?> waitForWith(
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
