import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:stem/src/workflow/core/workflow_execution_context.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

/// Context provided to each workflow step invocation.
///
/// The engine replays a step from the beginning whenever the run resumes from a
/// suspension (sleep, awaited event, manual rewind). Steps should therefore
/// treat `sleep`/`awaitEvent` as signalling mechanisms rather than control-flow
/// exits. Use [takeResumeData] to distinguish between the initial invocation
/// and resumption payloads supplied by the runtime.
///
/// [iteration] indicates how many times the step has already completed when
/// `autoVersion` is enabled, allowing handlers to branch per loop iteration or
/// derive unique identifiers.
class FlowContext implements WorkflowExecutionContext {
  /// Creates a workflow step context.
  FlowContext({
    required this.workflow,
    required this.runId,
    required this.stepName,
    required this.params,
    required this.previousResult,
    required this.stepIndex,
    this.iteration = 0,
    WorkflowClock clock = const SystemWorkflowClock(),
    Object? resumeData,
    this.enqueuer,
    this.workflows,
  }) : _clock = clock,
       _resumeData = resumeData;

  /// Name of the workflow.
  @override
  final String workflow;

  /// Identifier of the workflow run.
  @override
  final String runId;

  /// Name of the current step.
  @override
  final String stepName;

  /// Parameters passed when the workflow was started.
  @override
  final Map<String, Object?> params;

  /// Result of the previous step, if any.
  @override
  final Object? previousResult;

  /// Zero-based index of the current step.
  @override
  final int stepIndex;

  /// Current iteration when auto-versioning is enabled.
  @override
  final int iteration;

  /// Optional enqueuer for scheduling tasks with workflow metadata.
  @override
  final TaskEnqueuer? enqueuer;

  /// Optional typed workflow caller for spawning child workflows.
  @override
  final WorkflowCaller? workflows;
  final WorkflowClock _clock;

  FlowStepControl? _control;
  Object? _resumeData;

  /// Suspends the workflow until the delay elapses.
  ///
  /// After the delay, the worker replays the **same step** from the top. To
  /// avoid re-scheduling the sleep repeatedly, stash a marker in [data] and
  /// branch on [takeResumeData]; for example:
  ///
  /// ```dart
  /// final resume = ctx.takeResumeData();
  /// if (resume != true) {
  ///   ctx.sleep(const Duration(seconds: 1));
  ///   return null;
  /// }
  /// ```
  FlowStepControl sleep(Duration duration, {Map<String, Object?>? data}) {
    // When resuming from a previous sleep we may already have a wake timestamp
    // in the resume payload. Avoid re-suspending if the delay has elapsed.
    final resume = _resumeData;
    if (resume is Map<String, Object?>) {
      final type = resume['type'];
      final resumeAtRaw = resume['resumeAt'];
      if (type == 'sleep' && resumeAtRaw is String) {
        final resumeAt = DateTime.tryParse(resumeAtRaw);
        if (resumeAt != null && !resumeAt.isAfter(_clock.now())) {
          _control = FlowStepControl.continueRun();
          return _control!;
        }
      }
    }
    _control = FlowStepControl.sleep(duration, data: data);
    return _control!;
  }

  /// Suspends the workflow for [duration] with a JSON-serializable DTO payload.
  FlowStepControl sleepJson<T>(Duration duration, T value, {String? typeName}) {
    return sleep(
      duration,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(value, typeName: typeName),
      ),
    );
  }

  /// Suspends the workflow for [duration] with a versioned DTO payload.
  FlowStepControl sleepVersionedJson<T>(
    Duration duration,
    T value, {
    required int version,
    String? typeName,
  }) {
    return sleep(
      duration,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          value,
          version: version,
          typeName: typeName,
        ),
      ),
    );
  }

  /// Suspends the workflow until an event with [topic] is emitted.
  ///
  /// When the event bus resumes the run, the payload is made available via
  /// [takeResumeData]. Steps should always read and clear the payload to avoid
  /// processing the same message on subsequent replays.
  FlowStepControl awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    _control = FlowStepControl.awaitTopic(
      topic,
      deadline: deadline,
      data: data,
    );
    return _control!;
  }

  /// Suspends the workflow until [topic] arrives with a DTO payload.
  FlowStepControl awaitEventJson<T>(
    String topic,
    T value, {
    DateTime? deadline,
    String? typeName,
  }) {
    return awaitEvent(
      topic,
      deadline: deadline,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(value, typeName: typeName),
      ),
    );
  }

  /// Suspends the workflow until [topic] arrives with a versioned DTO payload.
  FlowStepControl awaitEventVersionedJson<T>(
    String topic,
    T value, {
    required int version,
    DateTime? deadline,
    String? typeName,
  }) {
    return awaitEvent(
      topic,
      deadline: deadline,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          value,
          version: version,
          typeName: typeName,
        ),
      ),
    );
  }

  @override
  void suspendFor(Duration duration, {Map<String, Object?>? data}) {
    sleep(duration, data: data);
  }

  @override
  void waitForTopic(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    awaitEvent(topic, deadline: deadline, data: data);
  }

  /// Injects a payload that will be returned the next time [takeResumeData] is
  /// called. Primarily used by the runtime; tests may also leverage it to mock
  /// resumption data.
  /// Stores resume data to be consumed by [takeResumeData].
  // ignore: use_setters_to_change_properties
  void resumeWith(Object? payload) {
    _resumeData = payload;
  }

  /// Returns the payload supplied when the run was resumed, or `null` if this
  /// is the first invocation.
  ///
  /// The method consumes the payload so subsequent calls during the same step
  /// return `null`. This makes it safe to guard control-flow with a simple
  /// `if (takeResumeData() == null) { ... }` pattern.
  @override
  Object? takeResumeData() {
    final value = _resumeData;
    _resumeData = null;
    return value;
  }

  /// Consumes the control directive queued by [sleep] or [awaitEvent]. Steps do
  /// not normally call this directly; it exists for the runtime orchestrator.
  FlowStepControl? takeControl() {
    final value = _control;
    _control = null;
    return value;
  }

  /// Returns a stable idempotency key derived from the workflow, run, and
  /// [scope]. Defaults to the current [stepName] (including iteration suffix
  /// when [iteration] > 0) when no scope is provided.
  @override
  String idempotencyKey([String? scope]) {
    final defaultScope = iteration > 0 ? '$stepName#$iteration' : stepName;
    final effectiveScope = (scope == null || scope.isEmpty)
        ? defaultScope
        : scope;
    return '$workflow/$runId/$effectiveScope';
  }

  /// Enqueues a task using the workflow-scoped enqueuer.
  ///
  /// Workflow metadata propagation is handled by the runtime-provided
  /// enqueuer implementation.
  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = enqueuer;
    if (delegate == null) {
      throw StateError('FlowContext has no enqueuer configured');
    }
    return delegate.enqueue(
      name,
      args: args,
      headers: headers,
      meta: meta,
      options: options,
      notBefore: notBefore,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Enqueues a typed task call using the workflow-scoped enqueuer.
  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = enqueuer;
    if (delegate == null) {
      throw StateError('FlowContext has no enqueuer configured');
    }
    return delegate.enqueueCall(call, enqueueOptions: enqueueOptions);
  }

  /// Starts a typed child workflow using the workflow-scoped caller.
  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final caller = workflows;
    if (caller == null) {
      throw StateError('FlowContext has no workflow caller configured');
    }
    return caller.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts a prebuilt child workflow call using the workflow-scoped caller.
  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) async {
    final caller = workflows;
    if (caller == null) {
      throw StateError('FlowContext has no workflow caller configured');
    }
    return caller.startWorkflowCall(call);
  }

  /// Waits for a typed child workflow run using the workflow-scoped caller.
  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    final caller = workflows;
    if (caller == null) {
      throw StateError('FlowContext has no workflow caller configured');
    }
    return caller.waitForWorkflowRef(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}
