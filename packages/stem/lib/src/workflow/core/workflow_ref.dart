import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';

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
