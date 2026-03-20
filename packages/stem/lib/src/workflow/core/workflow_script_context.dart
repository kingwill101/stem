import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/workflow/core/flow_context.dart' show FlowContext;
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_execution_context.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

/// Runtime context exposed to workflow scripts. Implementations are provided by
/// the workflow runtime so scripts can execute with durable semantics.
abstract class WorkflowScriptContext {
  /// Name of the workflow currently executing.
  String get workflow;

  /// Identifier for the run. Useful when emitting logs or constructing
  /// idempotency keys.
  String get runId;

  /// Parameters supplied when the workflow was started.
  Map<String, Object?> get params;

  /// Invokes or replays a workflow checkpoint. The provided [handler]
  /// persists its return value and the resolved value is replayed on
  /// subsequent runs.
  Future<T> step<T>(
    String name,
    FutureOr<T> Function(WorkflowScriptStepContext context) handler, {
    bool autoVersion = false,
  });
}

/// Typed read helpers for workflow start parameters in script run methods.
extension WorkflowScriptContextParams on WorkflowScriptContext {
  /// Returns the decoded workflow parameter for [key], or `null`.
  T? param<T>(String key, {PayloadCodec<T>? codec}) {
    return params.value<T>(key, codec: codec);
  }

  /// Returns the decoded workflow parameter for [key], or [fallback].
  T paramOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return params.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded workflow parameter for [key], throwing when absent.
  T requiredParam<T>(String key, {PayloadCodec<T>? codec}) {
    return params.requiredValue<T>(key, codec: codec);
  }

  /// Returns the decoded workflow parameter DTO for [key], or `null`.
  T? paramJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded workflow parameter DTO for [key], or [fallback].
  T paramJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.valueJsonOr<T>(
      key,
      fallback,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded workflow parameter DTO for [key], throwing when
  /// absent.
  T requiredParamJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.requiredValueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }
}

/// Context provided to each script checkpoint invocation. Mirrors
/// [FlowContext] but tailored for the facade helpers.
abstract class WorkflowScriptStepContext implements WorkflowExecutionContext {
  /// Name of the workflow currently executing.
  @override
  String get workflow;

  /// Identifier for the workflow run.
  @override
  String get runId;

  /// Name of the current checkpoint.
  @override
  String get stepName;

  /// Zero-based checkpoint index in the workflow definition.
  @override
  int get stepIndex;

  /// Iteration count for looped checkpoints.
  @override
  int get iteration;

  /// Parameters provided when the workflow started.
  @override
  Map<String, Object?> get params;

  /// Result of the previous checkpoint, if any.
  @override
  Object? get previousResult;

  /// Schedules a wake-up after [duration]. The workflow suspends once the
  /// checkpoint handler returns.
  Future<void> sleep(Duration duration, {Map<String, Object?>? data});

  /// Suspends the workflow until the given [topic] is emitted.
  Future<void> awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  });

  /// Returns and clears the resume payload provided by the runtime when the
  /// checkpoint resumes after a suspension.
  @override
  Object? takeResumeData();

  @override
  Future<void> suspendFor(
    Duration duration, {
    Map<String, Object?>? data,
  }) {
    return sleep(duration, data: data);
  }

  @override
  Future<void> waitForTopic(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    return awaitEvent(topic, deadline: deadline, data: data);
  }

  /// Returns a stable idempotency key derived from workflow/run/checkpoint.
  @override
  String idempotencyKey([String? scope]);

  /// Optional enqueuer for scheduling tasks with workflow metadata.
  @override
  TaskEnqueuer? get enqueuer;

  /// Optional typed workflow caller for spawning child workflows.
  @override
  WorkflowCaller? get workflows;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  });

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  });

  /// Starts a typed child workflow using this checkpoint context.
  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  });

  /// Starts a prebuilt child workflow call using this checkpoint context.
  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  );

  /// Waits for a typed child workflow using this checkpoint context.
  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  });
}
