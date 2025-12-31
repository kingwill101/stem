import 'dart:async';

import 'package:stem/src/workflow/core/flow_context.dart' show FlowContext;

import 'package:stem/src/workflow/workflow.dart' show FlowContext;

import 'package:stem/stem.dart' show FlowContext;

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

  /// Invokes or replays a workflow step. The provided [handler] persists its
  /// return value and the resolved value is replayed on subsequent runs.
  Future<T> step<T>(
    String name,
    FutureOr<T> Function(WorkflowScriptStepContext context) handler, {
    bool autoVersion = false,
  });
}

/// Context provided to each script step invocation. Mirrors [FlowContext] but
/// tailored for the facade helpers.
abstract class WorkflowScriptStepContext {
  /// Name of the workflow currently executing.
  String get workflow;

  /// Identifier for the workflow run.
  String get runId;

  /// Name of the current step.
  String get stepName;

  /// Zero-based step index in the workflow definition.
  int get stepIndex;

  /// Iteration count for looped steps.
  int get iteration;

  /// Parameters provided when the workflow started.
  Map<String, Object?> get params;

  /// Result of the previous step, if any.
  Object? get previousResult;

  /// Schedules a wake-up after [duration]. The workflow suspends once the step
  /// handler returns.
  Future<void> sleep(Duration duration, {Map<String, Object?>? data});

  /// Suspends the workflow until the given [topic] is emitted.
  Future<void> awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  });

  /// Returns and clears the resume payload provided by the runtime when the
  /// step resumes after a suspension.
  Object? takeResumeData();

  /// Returns a stable idempotency key derived from workflow/run/step.
  String idempotencyKey([String? scope]);
}
