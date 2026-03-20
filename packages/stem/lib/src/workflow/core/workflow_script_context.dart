import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/flow_context.dart' show FlowContext;
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
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

/// Context provided to each script checkpoint invocation. Mirrors
/// [FlowContext] but tailored for the facade helpers.
abstract class WorkflowScriptStepContext
    implements TaskEnqueuer, WorkflowCaller {
  /// Name of the workflow currently executing.
  String get workflow;

  /// Identifier for the workflow run.
  String get runId;

  /// Name of the current checkpoint.
  String get stepName;

  /// Zero-based checkpoint index in the workflow definition.
  int get stepIndex;

  /// Iteration count for looped checkpoints.
  int get iteration;

  /// Parameters provided when the workflow started.
  Map<String, Object?> get params;

  /// Result of the previous checkpoint, if any.
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
  Object? takeResumeData();

  /// Returns a stable idempotency key derived from workflow/run/checkpoint.
  String idempotencyKey([String? scope]);

  /// Optional enqueuer for scheduling tasks with workflow metadata.
  TaskEnqueuer? get enqueuer;

  /// Optional typed workflow caller for spawning child workflows.
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

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  });

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  );

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  });
}
