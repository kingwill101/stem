/// Durable workflow execution runtime.
///
/// This library provides the [WorkflowRuntime], which is responsible for
/// executing workflows defined via the `WorkflowDefinition` API.
///
/// ## Durability and Idempotency
///
/// The runtime is designed to be durable across worker crashes or restarts.
/// It achieves this by:
/// 1. Persisting every step result to the [WorkflowStore].
/// 2. Re-executing the workflow from the beginning on every "tick".
/// 3. Skipping steps that already have a persisted result.
///
/// Because of this "re-run" model, all code inside a workflow (including
/// non-flow-step logic) MUST be idempotent or strictly rely on the
/// provided [WorkflowScriptContext] for side effects.
///
/// ## Execution Model
///
/// Workflows are triggered by enqueuing a special `stem.workflow.run` task.
/// The [WorkflowRuntime] consumes these tasks and "ticks" the workflow
/// state machine until completion or suspension.
///
/// See also:
/// - `WorkflowDefinition` for defining flows and scripts.
/// - `WorkflowStore` for the persistence layer.
library;

import 'dart:async';

import 'package:contextual/contextual.dart' show Context;
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/signals/emitter.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:stem/src/workflow/core/event_bus.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
import 'package:stem/src/workflow/core/workflow_resume.dart';
import 'package:stem/src/workflow/core/workflow_runtime_metadata.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/runtime/workflow_introspection.dart';
import 'package:stem/src/workflow/runtime/workflow_manifest.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';
import 'package:stem/src/workflow/runtime/workflow_views.dart';
import 'package:uuid/uuid.dart';

/// Task name used for workflow run execution tasks.
const String workflowRunTaskName = 'stem.workflow.run';

/// Large retry budget to avoid dropping workflow run tasks on lease conflicts.
const int _leaseConflictMaxRetries = 1000000;

/// Coordinates execution of workflow runs by dequeuing tasks, invoking steps,
/// and persisting progress via a [WorkflowStore].
///
/// The runtime is durable: each step is re-executed from the top after a
/// suspension or worker crash. Handlers must therefore be idempotent and rely
/// on persisted step outputs or resume payloads to detect prior progress.
class WorkflowRuntime implements WorkflowCaller, WorkflowEventEmitter {
  /// Creates a workflow runtime backed by a [Stem] instance and
  /// [WorkflowStore].
  WorkflowRuntime({
    required Stem stem,
    required WorkflowStore store,
    required EventBus eventBus,
    WorkflowClock clock = const SystemWorkflowClock(),
    Duration pollInterval = const Duration(milliseconds: 500),
    this.leaseExtension = const Duration(seconds: 30),
    this.runLeaseDuration = const Duration(seconds: 30),
    this.queue = 'workflow',
    String? continuationQueue,
    String? executionQueue,
    WorkflowRegistry? registry,
    WorkflowIntrospectionSink? introspectionSink,
    String? runtimeId,
  }) : _stem = stem,
       _store = store,
       _eventBus = eventBus,
       _clock = clock,
       _pollInterval = pollInterval,
       _registry = registry ?? InMemoryWorkflowRegistry(),
       _introspection =
           introspectionSink ?? const NoopWorkflowIntrospectionSink(),
       continuationQueue = _resolveQueueName(
         continuationQueue,
         fallback: queue,
       ),
       executionQueue = _resolveQueueName(
         executionQueue,
         fallback: 'default',
       ),
       _runtimeId = runtimeId ?? _defaultRuntimeId();

  final Stem _stem;
  final WorkflowStore _store;
  final EventBus _eventBus;
  final Duration _pollInterval;

  /// Duration used when extending worker leases for workflow runs.
  final Duration leaseExtension;

  /// Duration used when claiming and renewing workflow run leases.
  final Duration runLeaseDuration;
  final WorkflowRegistry _registry;
  final WorkflowIntrospectionSink _introspection;
  final String _runtimeId;

  /// Queue name used to enqueue workflow run tasks.
  final String queue;

  /// Queue used for continuation tasks after suspension/event delivery.
  final String continuationQueue;

  /// Default queue for step-spawned execution channel tasks.
  final String executionQueue;
  final WorkflowClock _clock;
  final StemSignalEmitter _signals = const StemSignalEmitter(
    defaultSender: 'workflow',
  );

  Timer? _timer;
  bool _started = false;

  /// Registry of workflow definitions.
  WorkflowRegistry get registry => _registry;

  /// Clock used for scheduling and timeout calculations.
  WorkflowClock get clock => _clock;

  /// Registers a workflow definition so it can be scheduled via
  /// [startWorkflow]. Typically invoked by `StemWorkflowApp` during startup.
  void registerWorkflow(WorkflowDefinition definition) {
    _registry.register(definition);
  }

  /// Returns typed manifest entries for all registered workflows.
  List<WorkflowManifestEntry> workflowManifest() {
    return _registry.all
        .map((definition) => definition.toManifestEntry())
        .toList(growable: false);
  }

  /// Persists a new workflow run and enqueues it for execution.
  ///
  /// Throws [ArgumentError] if the workflow name is unknown. The returned run
  /// identifier can be used to poll with `WorkflowStore.get`.
  Future<String> startWorkflow(
    String name, {
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,

    /// Optional policy that caps runtime and suspension duration, causing the
    /// run to auto-cancel when limits are exceeded.
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final definition = _registry.lookup(name);
    if (definition == null) {
      throw ArgumentError.value(name, 'name', 'Workflow is not registered');
    }
    final requestedRunId = const Uuid().v7();
    final runtimeMetadata = WorkflowRunRuntimeMetadata(
      workflowId: definition.stableId,
      orchestrationQueue: queue,
      continuationQueue: continuationQueue,
      executionQueue: executionQueue,
      serializationFormat: _stem.payloadEncoders.defaultArgsEncoder.id,
      serializationVersion: '1',
      frameFormat: 'stem-envelope',
      frameVersion: '1',
      encryptionScope: _stem.signer != null ? 'signed-envelope' : 'none',
      encryptionEnabled: _stem.signer != null,
      streamId: '${name}_$requestedRunId',
    );
    final persistedParams = runtimeMetadata.attachToParams(
      params,
      parentRunId: parentRunId,
    );
    final runId = await _store.createRun(
      runId: requestedRunId,
      workflow: name,
      params: persistedParams,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
    await _signals.workflowRunStarted(
      WorkflowRunPayload(
        runId: runId,
        workflow: name,
        status: WorkflowRunStatus.running,
      ),
    );
    await _enqueueRun(
      runId,
      workflow: name,
      continuation: false,
      reason: WorkflowContinuationReason.start,
      runtimeMetadata: runtimeMetadata,
    );
    return runId;
  }

  /// Persists a new workflow run from a DTO that already exposes `toJson()`.
  Future<String> startWorkflowJson<T extends Object>(
    String name,
    T paramsJson, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    String? typeName,
  }) {
    return startWorkflow(
      name,
      params: Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(
          paramsJson,
          typeName: typeName ?? '$T',
        ),
      ),
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Persists a new workflow run from a DTO and stores a schema [version]
  /// beside the JSON payload.
  Future<String> startWorkflowVersionedJson<T extends Object>(
    String name,
    T paramsJson, {
    required int version,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    String? typeName,
  }) {
    return startWorkflow(
      name,
      params: Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          paramsJson,
          version: version,
          typeName: typeName ?? '$T',
        ),
      ),
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts a workflow from a typed [WorkflowRef].
  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return startWorkflow(
      definition.name,
      params: definition.encodeParams(params),
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Starts a workflow from a prebuilt [WorkflowStartCall].
  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return startWorkflowRef(
      call.definition,
      call.params,
      parentRunId: call.parentRunId,
      ttl: call.ttl,
      cancellationPolicy: call.cancellationPolicy,
    );
  }

  /// Waits for [runId] to reach a terminal state.
  Future<WorkflowResult<T>?> waitForCompletion<T extends Object?>(
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
    T Function(Object? payload)? decode,
    T Function(Map<String, dynamic> payload)? decodeJson,
  }) async {
    assert(
      decode == null || decodeJson == null,
      'Specify either decode or decodeJson, not both.',
    );
    final startedAt = _clock.now();
    while (true) {
      final state = await _store.get(runId);
      if (state == null) {
        return null;
      }
      if (state.isTerminal) {
        return _buildResult(
          state,
          decode,
          decodeJson: decodeJson,
          timedOut: false,
        );
      }
      if (timeout != null && _clock.now().difference(startedAt) >= timeout) {
        return _buildResult(
          state,
          decode,
          decodeJson: decodeJson,
          timedOut: true,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Waits for [runId] using the decoding rules from a [WorkflowRef].
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return waitForCompletion<TResult>(
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
      decode: definition.decode,
    );
  }

  /// Emits an external event and resumes all runs waiting on [topic].
  ///
  /// Each resumed run receives the event as `resumeData` for the awaiting step
  /// before being re-enqueued.
  Future<void> emit(String topic, Map<String, Object?> payload) async {
    await _eventBus.emit(topic, payload);
    const batchSize = 256;
    while (true) {
      final resolutions = await _store.resolveWatchers(
        topic,
        payload,
      );
      if (resolutions.isEmpty) {
        break;
      }
      for (final resolution in resolutions) {
        final state = await _store.get(resolution.runId);
        if (state == null) {
          continue;
        }
        final now = _clock.now();
        if (await _maybeCancelForPolicy(state, now: now)) {
          continue;
        }
        await _enqueueRun(
          resolution.runId,
          workflow: state.workflow,
          continuation: true,
          reason: WorkflowContinuationReason.event,
          runtimeMetadata: state.runtimeMetadata,
        );
      }
      if (resolutions.length < batchSize) {
        break;
      }
    }
  }

  /// Emits a DTO-backed external event without requiring a manual payload map.
  Future<void> emitJson<T extends Object>(
    String topic,
    T payloadJson, {
    String? typeName,
  }) {
    return emit(
      topic,
      Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(
          payloadJson,
          typeName: typeName ?? '$T',
        ),
      ),
    );
  }

  /// Emits a DTO-backed external event and stores a schema [version] beside
  /// the JSON payload.
  Future<void> emitVersionedJson<T extends Object>(
    String topic,
    T payloadJson, {
    required int version,
    String? typeName,
  }) {
    return emit(
      topic,
      Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          payloadJson,
          version: version,
          typeName: typeName ?? '$T',
        ),
      ),
    );
  }

  WorkflowResult<T> _buildResult<T extends Object?>(
    RunState state,
    T Function(Object? payload)? decode, {
    required bool timedOut,
    T Function(Map<String, dynamic> payload)? decodeJson,
  }) {
    final value = state.status == WorkflowStatus.completed
        ? _decodeResult(state.result, decode, decodeJson)
        : null;
    return WorkflowResult<T>(
      runId: state.id,
      status: state.status,
      state: state,
      value: value,
      rawResult: state.result,
      timedOut: timedOut && !state.isTerminal,
    );
  }

  T? _decodeResult<T extends Object?>(
    Object? payload,
    T Function(Object? payload)? decode,
    T Function(Map<String, dynamic> payload)? decodeJson,
  ) {
    if (decode != null) {
      return decode(payload);
    }
    if (decodeJson != null) {
      return decodeJson(
        PayloadCodec.decodeJsonMap(payload, typeName: 'workflow result'),
      );
    }
    return payload as T?;
  }

  /// Emits a typed external event that serializes to the existing map-based
  /// workflow event transport.
  ///
  /// When [codec] is provided, [value] is encoded before being emitted. The
  /// encoded value must be a `Map<String, Object?>` because workflow watcher
  /// resolution and event transport are currently map-shaped.
  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) {
    final encoded = codec != null ? codec.encodeDynamic(value) : value;
    return emit(topic, _coerceEventPayload(topic, encoded));
  }

  /// Emits a typed external event using a [WorkflowEventRef].
  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    return emitValue(event.topic, value, codec: event.codec);
  }

  /// Starts periodic polling that resumes runs whose wake-up time has elapsed.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(_pollInterval, (_) async {
      final now = _clock.now();
      final due = await _store.dueRuns(now);
      for (final runId in due) {
        final state = await _store.get(runId);
        if (state == null) {
          continue;
        }
        if (await _maybeCancelForPolicy(state, now: now)) {
          continue;
        }
        await _store.markResumed(runId, data: state.suspensionData);
        await _enqueueRun(
          runId,
          workflow: state.workflow,
          continuation: true,
          reason: WorkflowContinuationReason.due,
          runtimeMetadata: state.runtimeMetadata,
        );
      }
    });
  }

  /// Stops polling timers and prevents further automatic resumes.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// Transitions a running workflow to [WorkflowStatus.cancelled].
  Future<void> cancelWorkflow(String runId) async {
    final state = await _store.get(runId);
    await _store.cancel(runId);
    if (state != null) {
      await _signals.workflowRunCancelled(
        WorkflowRunPayload(
          runId: runId,
          workflow: state.workflow,
          status: WorkflowRunStatus.cancelled,
        ),
      );
    }
  }

  /// Exposes the task handler that executes workflow steps.
  TaskHandler<void> workflowRunnerHandler() =>
      _WorkflowRunTaskHandler(runtime: this);

  /// Returns a uniform run view for dashboard/CLI drilldowns.
  Future<WorkflowRunView?> viewRun(String runId) async {
    final state = await _store.get(runId);
    if (state == null) return null;
    return WorkflowRunView.fromState(state);
  }

  /// Returns persisted checkpoint views for [runId].
  Future<List<WorkflowCheckpointView>> viewCheckpoints(String runId) async {
    final state = await _store.get(runId);
    if (state == null) return const [];
    final checkpoints = await _store.listSteps(runId);
    return checkpoints
        .map(
          (entry) => WorkflowCheckpointView.fromEntry(
            runId: runId,
            workflow: state.workflow,
            entry: entry,
          ),
        )
        .toList(growable: false);
  }

  /// Returns combined run+checkpoint drilldown view for [runId].
  Future<WorkflowRunDetailView?> viewRunDetail(String runId) async {
    final run = await viewRun(runId);
    if (run == null) return null;
    final checkpoints = await viewCheckpoints(runId);
    return WorkflowRunDetailView(run: run, checkpoints: checkpoints);
  }

  /// Returns uniform run views filtered by workflow/status.
  Future<List<WorkflowRunView>> listRunViews({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final runs = await _store.listRuns(
      workflow: workflow,
      status: status,
      limit: limit,
      offset: offset,
    );
    return runs.map(WorkflowRunView.fromState).toList(growable: false);
  }

  /// Executes steps for [runId] until completion or the next suspension.
  ///
  /// Safe to invoke multiple times; if the run is already terminal the call is
  /// a no-op.
  Future<void> executeRun(String runId, {TaskContext? taskContext}) async {
    final runState = await _store.get(runId);
    if (runState == null) {
      return;
    }
    if (runState.isTerminal) {
      return;
    }
    if (runState.status == WorkflowStatus.suspended) {
      final now = _clock.now();
      if (await _maybeCancelForPolicy(runState, now: now)) {
        return;
      }
    }
    // Attempt to claim the run lease before executing steps.
    final claimed = await _store.claimRun(
      runId,
      ownerId: _runtimeId,
      leaseDuration: runLeaseDuration,
    );
    if (!claimed) {
      // Reschedule the run so we don't ack and drop a redelivered task.
      throw TaskRetryRequest(
        countdown: runLeaseDuration,
        maxRetries: _leaseConflictMaxRetries,
      );
    }
    final now = _clock.now();
    if (await _maybeCancelForPolicy(runState, now: now)) {
      await _store.releaseRun(runId, ownerId: _runtimeId);
      return;
    }
    final definition = _registry.lookup(runState.workflow);
    if (definition == null) {
      await _store.markFailed(
        runId,
        StateError('Unknown workflow ${runState.workflow}'),
        StackTrace.current,
        terminal: true,
      );
      await _signals.workflowRunFailed(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.failed,
          metadata: {'error': 'Unknown workflow ${runState.workflow}'},
        ),
      );
      await _store.releaseRun(runId, ownerId: _runtimeId);
      return;
    }

    try {
      final wasSuspended = runState.status == WorkflowStatus.suspended;
      await _store.markRunning(runId);
      if (wasSuspended) {
        stemLogger.debug(
          'Workflow {workflow} resumed',
          _runtimeLogContext(
            workflow: runState.workflow,
            runId: runId,
            extra: {'runtimeId': _runtimeId},
          ),
        );
        await _signals.workflowRunResumed(
          WorkflowRunPayload(
            runId: runId,
            workflow: runState.workflow,
            status: WorkflowRunStatus.running,
          ),
        );
      }

      if (definition.isScript) {
        await _executeScript(definition, runState, taskContext: taskContext);
        return;
      }

      final policy = runState.cancellationPolicy;
      final suspensionData = runState.suspensionData;
      final completedIterations = await _loadCompletedIterations(runId);
      var cursor = _computeCursor(definition, runState, completedIterations);
      Object? previousResult;
      if (cursor > 0) {
        final prevStep = definition.steps[cursor - 1];
        final completedCount = completedIterations[prevStep.name] ?? 0;
        if (completedCount > 0) {
          final checkpoint = _checkpointName(prevStep, completedCount - 1);
          previousResult = prevStep.decodeValue(
            await _store.readStep(runId, checkpoint),
          );
        }
      }
      var resumeData = suspensionData?['payload'];

      while (cursor < definition.steps.length) {
        if (policy != null && policy.maxRunDuration != null) {
          final elapsed = _clock.now().difference(runState.createdAt);
          if (elapsed >= policy.maxRunDuration!) {
            await _cancelForPolicy(
              runState,
              reason: 'maxRunDuration',
              metadata: {
                'elapsedMillis': elapsed.inMilliseconds,
                'limitMillis': policy.maxRunDuration!.inMilliseconds,
              },
            );
            return;
          }
        }
        final step = definition.steps[cursor];
        final iteration = step.autoVersion
            ? _currentIterationForStep(
                step,
                completedIterations,
                suspensionData,
              )
            : 0;
        final checkpointName = step.autoVersion
            ? _versionedName(step.name, iteration)
            : step.name;

        if (iteration > 0) {
          await _recordStepEvent(
            WorkflowStepEventType.retrying,
            runState,
            step.name,
            iteration: iteration,
          );
        }
        await _store.markRunning(runId, stepName: step.name);
        await _extendLeases(taskContext, runId);
        await _recordStepEvent(
          WorkflowStepEventType.started,
          runState,
          step.name,
          iteration: iteration,
        );
        await _signals.workflowRunResumed(
          WorkflowRunPayload(
            runId: runId,
            workflow: runState.workflow,
            status: WorkflowRunStatus.running,
            step: step.name,
          ),
        );

        final cached = await _store.readStep<Object?>(runId, checkpointName);
        if (cached != null) {
          previousResult = step.decodeValue(cached);
          await _recordStepEvent(
            WorkflowStepEventType.completed,
            runState,
            step.name,
            iteration: iteration,
            result: cached,
            metadata: const {'replayed': true},
          );
          cursor += 1;
          await _extendLeases(taskContext, runId);
          continue;
        }

        final stepMeta = _stepMeta(
          runState: runState,
          stepName: step.name,
          stepIndex: cursor,
          iteration: iteration,
        );
        final context = FlowContext(
          workflow: runState.workflow,
          runId: runId,
          stepName: step.name,
          params: runState.workflowParams,
          previousResult: previousResult,
          stepIndex: cursor,
          iteration: iteration,
          clock: _clock,
          resumeData: resumeData,
          enqueuer: _stepEnqueuer(
            taskContext: taskContext,
            baseMeta: stepMeta,
            targetExecutionQueue: runState.executionQueue,
          ),
          workflows: _ChildWorkflowCaller(runtime: this, parentRunId: runId),
        );
        resumeData = null;
        dynamic result;
        var suspendedBySignal = false;
        try {
          result = await TaskEnqueueScope.run(
            stepMeta,
            () async => await step.handler(context),
          );
        } on WorkflowSuspensionSignal {
          suspendedBySignal = true;
        } on _WorkflowLeaseLost {
          return;
        } catch (error, stack) {
          await _store.markFailed(runId, error, stack);
          stemLogger.warning(
            'Workflow {workflow} failed',
            _runtimeLogContext(
              workflow: runState.workflow,
              runId: runId,
              step: step.name,
              extra: {
                'error': error.toString(),
                'stack': stack.toString(),
                'runtimeId': _runtimeId,
              },
            ),
          );
          await _recordStepEvent(
            WorkflowStepEventType.failed,
            runState,
            step.name,
            iteration: iteration,
            error: error.toString(),
          );
          await _signals.workflowRunFailed(
            WorkflowRunPayload(
              runId: runId,
              workflow: runState.workflow,
              status: WorkflowRunStatus.failed,
              step: step.name,
              metadata: {'error': error.toString(), 'stack': stack.toString()},
            ),
          );
          rethrow;
        }
        final control = context.takeControl();
        if (control != null && control.type != FlowControlType.continueRun) {
          final metadata = <String, Object?>{
            'step': step.name,
            'iteration': iteration,
            'iterationStep': step.name,
          };
          final suspendedAt = _clock.now();
          metadata['suspendedAt'] = suspendedAt.toIso8601String();
          DateTime? policyDeadline;
          final suspendLimit = policy?.maxSuspendDuration;
          if (suspendLimit != null) {
            policyDeadline = suspendedAt.add(suspendLimit);
            metadata['policyDeadline'] = policyDeadline.toIso8601String();
          }
          if (control.type == FlowControlType.sleep) {
            final requestedResumeAt = suspendedAt.add(control.delay!);
            var resumeAt = requestedResumeAt;
            metadata['type'] = 'sleep';
            metadata['requestedResumeAt'] = requestedResumeAt.toIso8601String();
            if (policyDeadline != null && policyDeadline.isBefore(resumeAt)) {
              resumeAt = policyDeadline;
              metadata['policyDeadlineApplied'] = true;
            }
            metadata['resumeAt'] = resumeAt.toIso8601String();
            final controlData = control.data;
            if (controlData != null && controlData.isNotEmpty) {
              metadata.addAll(controlData);
            }
            metadata.putIfAbsent('payload', () => true);
            await _store.suspendUntil(
              runId,
              step.name,
              resumeAt,
              data: metadata,
            );
            await _signals.workflowRunSuspended(
              WorkflowRunPayload(
                runId: runId,
                workflow: runState.workflow,
                status: WorkflowRunStatus.suspended,
                step: step.name,
                metadata: {
                  'type': 'sleep',
                  'resumeAt': resumeAt.toIso8601String(),
                },
              ),
            );
            stemLogger.debug(
              'Workflow {workflow} suspended',
              _runtimeLogContext(
                workflow: runState.workflow,
                runId: runId,
                step: step.name,
                extra: {
                  'workflowSuspensionType': 'sleep',
                  'resumeAt': resumeAt.toIso8601String(),
                  'workflowIteration': iteration,
                  'runtimeId': _runtimeId,
                },
              ),
            );
          } else if (control.type == FlowControlType.waitForEvent) {
            metadata['type'] = 'event';
            metadata['topic'] = control.topic;
            var deadline = control.deadline;
            if (deadline != null) {
              metadata['deadline'] = deadline.toIso8601String();
            }
            if (policyDeadline != null) {
              if (deadline == null || policyDeadline.isBefore(deadline)) {
                deadline = policyDeadline;
                metadata['policyDeadlineApplied'] = true;
              }
            }
            final controlData = control.data;
            if (controlData != null && controlData.isNotEmpty) {
              metadata.addAll(controlData);
            }
            await _store.registerWatcher(
              runId,
              step.name,
              control.topic!,
              deadline: deadline,
              data: metadata,
            );
            await _signals.workflowRunSuspended(
              WorkflowRunPayload(
                runId: runId,
                workflow: runState.workflow,
                status: WorkflowRunStatus.suspended,
                step: step.name,
                metadata: {
                  'type': 'waitForEvent',
                  'topic': control.topic,
                  if (deadline != null) 'deadline': deadline.toIso8601String(),
                },
              ),
            );
            stemLogger.debug(
              'Workflow {workflow} suspended',
              _runtimeLogContext(
                workflow: runState.workflow,
                runId: runId,
                step: step.name,
                extra: {
                  'workflowSuspensionType': 'event',
                  'topic': control.topic!,
                  'workflowIteration': iteration,
                  if (deadline != null) 'deadline': deadline.toIso8601String(),
                  'runtimeId': _runtimeId,
                },
              ),
            );
          }
          return;
        }
        if (suspendedBySignal) {
          throw StateError(
            'Flow step "${step.name}" threw WorkflowSuspensionSignal without '
            'scheduling a suspension control.',
          );
        }

        final storedResult = step.encodeValue(result);
        await _store.saveStep(runId, checkpointName, storedResult);
        await _extendLeases(taskContext, runId);
        await _recordStepEvent(
          WorkflowStepEventType.completed,
          runState,
          step.name,
          iteration: iteration,
          result: storedResult,
        );
        if (step.autoVersion) {
          completedIterations[step.name] = iteration + 1;
        } else {
          completedIterations[step.name] = 1;
        }
        previousResult = result;
        cursor += 1;
      }

      final storedWorkflowResult = definition.encodeResult(previousResult);
      await _store.markCompleted(runId, storedWorkflowResult);
      stemLogger.debug(
        'Workflow {workflow} completed',
        _runtimeLogContext(
          workflow: runState.workflow,
          runId: runId,
          extra: {'runtimeId': _runtimeId},
        ),
      );
      await _signals.workflowRunCompleted(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.completed,
          metadata: {'result': storedWorkflowResult},
        ),
      );
    } on _WorkflowLeaseLost {
      return;
    } finally {
      await _store.releaseRun(runId, ownerId: _runtimeId);
    }
  }

  /// Executes a script-based workflow definition with resume handling.
  Future<void> _executeScript(
    WorkflowDefinition definition,
    RunState runState, {
    TaskContext? taskContext,
  }) async {
    final script = definition.scriptBody;
    if (script == null) {
      return;
    }
    final runId = runState.id;
    final wasSuspended = runState.status == WorkflowStatus.suspended;
    await _store.markRunning(runId);
    if (wasSuspended) {
      stemLogger.debug(
        'Workflow {workflow} resumed',
        _runtimeLogContext(
          workflow: runState.workflow,
          runId: runId,
          extra: {'runtimeId': _runtimeId},
        ),
      );
      await _signals.workflowRunResumed(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.running,
        ),
      );
    }
    final checkpoints = await _store.listSteps(runId);
    final completedIterations = await _loadCompletedIterations(runId);
    Object? previousResult;
    if (checkpoints.isNotEmpty) {
      previousResult =
          definition
              .checkpointByName(checkpoints.last.baseName)
              ?.decodeValue(checkpoints.last.value) ??
          checkpoints.last.value;
    }
    final execution = _WorkflowScriptExecution(
      runtime: this,
      runState: runState,
      taskContext: taskContext,
      completedIterations: completedIterations,
      definition: definition,
      previousResult: previousResult,
      initialStepIndex: checkpoints.length,
      suspensionData: runState.suspensionData,
      policy: runState.cancellationPolicy,
    );

    try {
      final result = await script(execution);
      if (execution.wasSuspended) {
        return;
      }
      final storedWorkflowResult = definition.encodeResult(result);
      await _store.markCompleted(runId, storedWorkflowResult);
      stemLogger.debug(
        'Workflow {workflow} completed',
        _runtimeLogContext(
          workflow: runState.workflow,
          runId: runId,
          extra: {'runtimeId': _runtimeId},
        ),
      );
      await _signals.workflowRunCompleted(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.completed,
          metadata: {'result': storedWorkflowResult},
        ),
      );
    } on _WorkflowLeaseLost {
      return;
    } on _WorkflowScriptSuspended {
      return;
    } catch (error, stack) {
      await _store.markFailed(runId, error, stack);
      stemLogger.warning(
        'Workflow {workflow} failed',
        _runtimeLogContext(
          workflow: runState.workflow,
          runId: runId,
          step: execution.lastStepName,
          extra: {
            'error': error.toString(),
            'stack': stack.toString(),
            'runtimeId': _runtimeId,
          },
        ),
      );
      await _signals.workflowRunFailed(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.failed,
          step: execution.lastStepName,
          metadata: {'error': error.toString(), 'stack': stack.toString()},
        ),
      );
      rethrow;
    }
  }

  /// Records a workflow step lifecycle event to the introspection sink.
  Future<void> _recordStepEvent(
    WorkflowStepEventType type,
    RunState runState,
    String stepName, {
    int? iteration,
    Object? result,
    String? error,
    Map<String, Object?>? metadata,
  }) async {
    try {
      await _introspection.recordStepEvent(
        WorkflowStepEvent(
          runId: runState.id,
          workflow: runState.workflow,
          stepId: stepName,
          type: type,
          timestamp: _clock.now(),
          iteration: iteration,
          result: result,
          error: error,
          metadata: metadata == null ? null : Map.unmodifiable(metadata),
        ),
      );
    } on Object catch (_) {
      // Ignore introspection failures to avoid impacting workflow execution.
    }
  }

  /// Records a runtime orchestration event to the introspection sink.
  Future<void> _recordRuntimeEvent({
    required String runId,
    required String workflow,
    required WorkflowRuntimeEventType type,
    Map<String, Object?>? metadata,
  }) async {
    try {
      await _introspection.recordRuntimeEvent(
        WorkflowRuntimeEvent(
          runId: runId,
          workflow: workflow,
          type: type,
          timestamp: _clock.now(),
          metadata: metadata == null ? null : Map.unmodifiable(metadata),
        ),
      );
    } on Object catch (_) {
      // Ignore introspection failures to avoid impacting workflow execution.
    }
  }

  /// Loads the latest iteration number for each step name.
  Future<Map<String, int>> _loadCompletedIterations(String runId) async {
    final entries = await _store.listSteps(runId);
    final counts = <String, int>{};
    for (final entry in entries) {
      final base = _basePersistedNodeName(entry.name);
      final suffix = _parseIterationSuffix(entry.name);
      final nextIndex = suffix != null ? suffix + 1 : 1;
      final current = counts[base] ?? 0;
      if (nextIndex > current) counts[base] = nextIndex;
    }
    return counts;
  }

  /// Computes the next step cursor from persisted state and suspension data.
  int _computeCursor(
    WorkflowDefinition definition,
    RunState runState,
    Map<String, int> completedIterations,
  ) {
    final suspendedStep = runState.suspensionData?['step'] as String?;
    if (suspendedStep != null) {
      final index = definition.steps.indexWhere((s) => s.name == suspendedStep);
      if (index >= 0) {
        return index;
      }
    }

    var cursor = 0;
    for (final step in definition.steps) {
      final completed = completedIterations[step.name] ?? 0;
      if (completed == 0) {
        break;
      }
      cursor += 1;
    }
    return cursor;
  }

  /// Resolves the current iteration index for a step.
  int _currentIterationForStep(
    FlowStep step,
    Map<String, int> completedIterations,
    Map<String, Object?>? suspensionData,
  ) {
    if (!step.autoVersion) return 0;
    final suspendedStep = suspensionData?['iterationStep'] as String?;
    if (suspendedStep == step.name) {
      final suspendedIteration = suspensionData?['iteration'] as int?;
      if (suspendedIteration != null) {
        return suspendedIteration;
      }
    }
    return completedIterations[step.name] ?? 0;
  }

  String _versionedName(String name, int iteration) => '$name#$iteration';

  String _checkpointName(FlowStep step, int iteration) =>
      step.autoVersion ? _versionedName(step.name, iteration) : step.name;

  /// Parses an iteration suffix from a versioned step name.
  int? _parseIterationSuffix(String name) {
    final hashIndex = name.lastIndexOf('#');
    if (hashIndex == -1) return null;
    final suffix = name.substring(hashIndex + 1);
    return int.tryParse(suffix);
  }

  /// Removes an iteration suffix from a persisted step/checkpoint name.
  String _basePersistedNodeName(String name) {
    final hashIndex = name.indexOf('#');
    if (hashIndex == -1) return name;
    return name.substring(0, hashIndex);
  }

  /// Extends the broker visibility timeout for the current workflow task.
  Future<void> _extendLease(TaskContext? context) async {
    if (context == null) return;
    if (leaseExtension.inMicroseconds <= 0) return;
    try {
      await context.extendLease(leaseExtension);
    } on Object {
      // Ignore lease extension failures; broker will fall back to default TTL.
    }
  }

  /// Renews the workflow run lease and the broker visibility timeout.
  Future<void> _extendLeases(TaskContext? context, String runId) async {
    if (runLeaseDuration.inMicroseconds > 0) {
      final renewed = await _store.renewRunLease(
        runId,
        ownerId: _runtimeId,
        leaseDuration: runLeaseDuration,
      );
      if (!renewed) {
        throw const _WorkflowLeaseLost();
      }
    }
    await _extendLease(context);
  }

  /// Generates a unique runtime identifier for workflow lease ownership.
  static String _defaultRuntimeId() => 'workflow-runtime-${const Uuid().v7()}';

  static String _resolveQueueName(String? raw, {required String fallback}) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;
    return trimmed;
  }

  /// Enqueues a workflow run execution task.
  Future<void> _enqueueRun(
    String runId, {
    String? workflow,
    required bool continuation,
    required WorkflowContinuationReason reason,
    WorkflowRunRuntimeMetadata? runtimeMetadata,
  }) async {
    final metadata =
        runtimeMetadata ??
        WorkflowRunRuntimeMetadata(
          workflowId: '',
          orchestrationQueue: queue,
          continuationQueue: continuationQueue,
          executionQueue: executionQueue,
        );
    final orchestrationQueue = _resolveQueueName(
      metadata.orchestrationQueue,
      fallback: queue,
    );
    final resolvedContinuationQueue = _resolveQueueName(
      metadata.continuationQueue,
      fallback: continuationQueue,
    );
    final resolvedExecutionQueue = _resolveQueueName(
      metadata.executionQueue,
      fallback: executionQueue,
    );
    final targetQueue = continuation
        ? resolvedContinuationQueue
        : orchestrationQueue;
    final meta = <String, Object?>{
      'stem.workflow.channel': WorkflowChannelKind.orchestration.name,
      'stem.workflow.runId': runId,
      'stem.workflow.continuation': continuation,
      'stem.workflow.continuationReason': reason.name,
      'stem.workflow.orchestrationQueue': orchestrationQueue,
      'stem.workflow.continuationQueue': resolvedContinuationQueue,
      'stem.workflow.executionQueue': resolvedExecutionQueue,
      'stem.workflow.serialization.format': metadata.serializationFormat,
      'stem.workflow.serialization.version': metadata.serializationVersion,
      'stem.workflow.frame.format': metadata.frameFormat,
      'stem.workflow.frame.version': metadata.frameVersion,
      'stem.workflow.encryption.scope': metadata.encryptionScope,
      'stem.workflow.encryption.enabled': metadata.encryptionEnabled,
      if (metadata.streamId != null)
        'stem.workflow.stream.id': metadata.streamId,
      if (metadata.workflowId.isNotEmpty)
        'stem.workflow.id': metadata.workflowId,
      if (workflow != null && workflow.isNotEmpty)
        'stem.workflow.name': workflow,
    };
    await _recordRuntimeEvent(
      runId: runId,
      workflow: workflow ?? '',
      type: WorkflowRuntimeEventType.continuationEnqueued,
      metadata: {
        'continuation': continuation,
        'reason': reason.name,
        'queue': targetQueue,
      },
    );
    await _stem.enqueue(
      workflowRunTaskName,
      args: {'runId': runId},
      meta: meta,
      options: TaskOptions(queue: targetQueue),
    );
    stemLogger.debug(
      'Workflow {workflow} enqueued',
      _runtimeLogContext(
        workflow: workflow ?? '',
        runId: runId,
        extra: {
          'workflowChannel': WorkflowChannelKind.orchestration.name,
          'workflowContinuation': continuation,
          'workflowReason': reason.name,
          'queue': targetQueue,
          'runtimeId': _runtimeId,
        },
      ),
    );
  }

  /// Builds workflow metadata injected into step task enqueues.
  Map<String, Object?> _stepMeta({
    required RunState runState,
    required String stepName,
    required int stepIndex,
    required int iteration,
  }) {
    final runtime = runState.runtimeMetadata;
    return Map<String, Object?>.unmodifiable({
      'stem.workflow.channel': WorkflowChannelKind.execution.name,
      'stem.workflow.name': runState.workflow,
      'stem.workflow.runId': runState.id,
      'stem.workflow.step': stepName,
      'stem.workflow.stepIndex': stepIndex,
      'stem.workflow.iteration': iteration,
      'stem.workflow.orchestrationQueue': runState.orchestrationQueue,
      'stem.workflow.continuationQueue': runState.continuationQueue,
      'stem.workflow.executionQueue': runState.executionQueue,
      'stem.workflow.serialization.format': runtime.serializationFormat,
      'stem.workflow.serialization.version': runtime.serializationVersion,
      'stem.workflow.frame.format': runtime.frameFormat,
      'stem.workflow.frame.version': runtime.frameVersion,
      'stem.workflow.encryption.scope': runtime.encryptionScope,
      'stem.workflow.encryption.enabled': runtime.encryptionEnabled,
      if (runtime.streamId != null) 'stem.workflow.stream.id': runtime.streamId,
      if (runtime.workflowId.isNotEmpty) 'stem.workflow.id': runtime.workflowId,
    });
  }

  /// Returns an enqueuer that injects workflow metadata for step tasks.
  TaskEnqueuer _stepEnqueuer({
    required Map<String, Object?> baseMeta,
    TaskContext? taskContext,
    String? targetExecutionQueue,
  }) {
    final delegate = taskContext ?? _stem;
    return _WorkflowStepEnqueuer(
      delegate: delegate,
      baseMeta: baseMeta,
      executionQueue: _resolveQueueName(
        targetExecutionQueue,
        fallback: executionQueue,
      ),
    );
  }

  Context _runtimeLogContext({
    required String workflow,
    required String runId,
    String? step,
    Map<String, Object?> extra = const {},
  }) {
    return stemLogContext(
      component: 'stem',
      subsystem: 'workflow',
      fields: {
        'workflow': workflow,
        'workflowRunId': runId,
        if (step != null && step.isNotEmpty) 'workflowStep': step,
        ...extra,
      },
    );
  }

  /// Returns true when a cancellation policy triggers a terminal cancel.
  Future<bool> _maybeCancelForPolicy(
    RunState state, {
    required DateTime now,
  }) async {
    if (state.isTerminal) {
      return false;
    }
    final policy = state.cancellationPolicy;
    if (policy == null || policy.isEmpty) {
      return false;
    }

    final maxRun = policy.maxRunDuration;
    if (maxRun != null) {
      final elapsed = now.difference(state.createdAt);
      if (elapsed >= maxRun) {
        await _cancelForPolicy(
          state,
          reason: 'maxRunDuration',
          metadata: {
            'elapsedMillis': elapsed.inMilliseconds,
            'limitMillis': maxRun.inMilliseconds,
          },
        );
        return true;
      }
    }

    final maxSuspend = policy.maxSuspendDuration;
    if (maxSuspend != null && state.status == WorkflowStatus.suspended) {
      final suspendedAtRaw = state.suspensionData?['suspendedAt'];
      DateTime? suspendedAt;
      if (suspendedAtRaw is String) {
        suspendedAt = DateTime.tryParse(suspendedAtRaw);
      }
      suspendedAt ??= state.updatedAt ?? state.createdAt;
      final elapsedSuspend = now.difference(suspendedAt);
      if (elapsedSuspend >= maxSuspend) {
        final metadata = <String, Object?>{
          'elapsedMillis': elapsedSuspend.inMilliseconds,
          'limitMillis': maxSuspend.inMilliseconds,
        };
        final suspendedStep = state.suspensionData?['step'];
        if (suspendedStep is String && suspendedStep.isNotEmpty) {
          metadata['step'] = suspendedStep;
        }
        await _cancelForPolicy(
          state,
          reason: 'maxSuspendDuration',
          metadata: metadata,
        );
        return true;
      }
    }

    return false;
  }

  /// Marks a workflow run as cancelled due to a [WorkflowCancellationPolicy]
  /// violation.
  ///
  /// This updates the [WorkflowStore] and emits a [WorkflowRunStatus.cancelled]
  /// signal. The [reason] should identify which policy limit was exceeded
  /// (e.g., 'maxRunDuration').
  Future<void> _cancelForPolicy(
    RunState state, {
    required String reason,
    required Map<String, Object?> metadata,
  }) async {
    await _store.cancel(state.id, reason: reason);
    final payloadMetadata = <String, Object?>{
      'policy': reason,
      'cancelledAt': _clock.now().toIso8601String(),
      ...metadata,
    };
    await _signals.workflowRunCancelled(
      WorkflowRunPayload(
        runId: state.id,
        workflow: state.workflow,
        status: WorkflowRunStatus.cancelled,
        metadata: payloadMetadata,
      ),
    );
  }
}

/// Task handler that dispatches workflow run execution for a run id.
class _WorkflowRunTaskHandler implements TaskHandler<void> {
  _WorkflowRunTaskHandler({required this.runtime});

  final WorkflowRuntime runtime;

  @override
  String get name => workflowRunTaskName;

  @override
  TaskOptions get options => TaskOptions(queue: runtime.queue, maxRetries: 5);

  @override
  TaskMetadata get metadata =>
      const TaskMetadata(description: 'Executes workflow runs');

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  /// Executes a workflow run based on the payload in the task args.
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final runId = args['runId'] as String?;
    if (runId == null) {
      throw ArgumentError('workflow.run missing runId');
    }
    await runtime.executeRun(runId, taskContext: context);
  }
}

/// Script-based workflow execution adapter with checkpointing and suspension.
class _WorkflowScriptExecution implements WorkflowScriptContext {
  _WorkflowScriptExecution({
    required this.runtime,
    required this.definition,
    required this.runState,
    required this.taskContext,
    required Map<String, int> completedIterations,
    required Object? previousResult,
    required int initialStepIndex,
    required this.policy,
    Map<String, Object?>? suspensionData,
  }) : _completedIterations = Map<String, int>.from(completedIterations),
       _previousResult = previousResult,
       _stepIndex = initialStepIndex,
       _resumePayload = suspensionData?['payload'],
       _suspensionStep =
           (suspensionData?['iterationStep'] ?? suspensionData?['step'])
               as String?,
       _suspensionIteration = suspensionData?['iteration'] as int?,
       clock = runtime.clock;

  final WorkflowRuntime runtime;
  final WorkflowDefinition definition;
  final RunState runState;
  final TaskContext? taskContext;
  final Map<String, int> _completedIterations;
  final WorkflowCancellationPolicy? policy;
  final WorkflowClock clock;
  Object? _previousResult;
  int _stepIndex;
  bool _wasSuspended = false;
  String? _lastStepName;
  String? _suspensionStep;
  int? _suspensionIteration;
  Object? _resumePayload;

  /// Whether a script checkpoint suspended the run.
  bool get wasSuspended => _wasSuspended;

  /// Last executed checkpoint name, if any.
  String? get lastStepName => _lastStepName;

  @override
  Map<String, Object?> get params => runState.workflowParams;

  @override
  String get runId => runState.id;

  @override
  String get workflow => runState.workflow;

  @override
  Future<T> step<T>(
    String name,
    FutureOr<T> Function(WorkflowScriptStepContext context) handler, {
    bool autoVersion = false,
  }) async {
    /// Executes a script checkpoint with replay and suspension handling.
    _lastStepName = name;
    final policy = this.policy;
    if (policy != null && policy.maxRunDuration != null) {
      final elapsed = clock.now().difference(runState.createdAt);
      if (elapsed >= policy.maxRunDuration!) {
        await runtime._cancelForPolicy(
          runState,
          reason: 'maxRunDuration',
          metadata: {
            'elapsedMillis': elapsed.inMilliseconds,
            'limitMillis': policy.maxRunDuration!.inMilliseconds,
          },
        );
        throw const _WorkflowScriptSuspended();
      }
    }
    final iteration = autoVersion ? _nextIteration(name) : 0;
    final checkpointName = autoVersion
        ? runtime._versionedName(name, iteration)
        : name;

    if (iteration > 0) {
      await runtime._recordStepEvent(
        WorkflowStepEventType.retrying,
        runState,
        name,
        iteration: iteration,
      );
    }
    await runtime._store.markRunning(runId, stepName: name);
    await runtime._extendLeases(taskContext, runId);
    await runtime._recordStepEvent(
      WorkflowStepEventType.started,
      runState,
      name,
      iteration: iteration,
    );
    await runtime._signals.workflowRunResumed(
      WorkflowRunPayload(
        runId: runId,
        workflow: workflow,
        status: WorkflowRunStatus.running,
        step: name,
      ),
    );

    final declaredCheckpoint = definition.checkpointByName(name);
    final cached = await runtime._store.readStep<Object?>(
      runId,
      checkpointName,
    );
    if (cached != null) {
      final decodedCached = declaredCheckpoint?.decodeValue(cached) ?? cached;
      _previousResult = decodedCached;
      await runtime._recordStepEvent(
        WorkflowStepEventType.completed,
        runState,
        name,
        iteration: iteration,
        result: cached,
        metadata: const {'replayed': true},
      );
      if (autoVersion) {
        _completedIterations[name] = iteration + 1;
      } else {
        _completedIterations[name] = 1;
      }
      _stepIndex += 1;
      await runtime._extendLeases(taskContext, runId);
      return decodedCached as T;
    }

    final resumeData = _takeResumePayload(name, autoVersion ? iteration : null);
    final stepMeta = runtime._stepMeta(
      runState: runState,
      stepName: name,
      stepIndex: _stepIndex,
      iteration: iteration,
    );
    final stepContext = _WorkflowScriptStepContextImpl(
      execution: this,
      stepName: name,
      stepIndex: _stepIndex,
      iteration: iteration,
      resumeData: resumeData,
      enqueuer: runtime._stepEnqueuer(
        taskContext: taskContext,
        baseMeta: stepMeta,
        targetExecutionQueue: runState.executionQueue,
      ),
      workflows: _ChildWorkflowCaller(runtime: runtime, parentRunId: runId),
    );
    late final T result;
    var suspendedBySignal = false;
    try {
      result = await TaskEnqueueScope.run(
        stepMeta,
        () async => await handler(stepContext),
      );
    } on WorkflowSuspensionSignal {
      suspendedBySignal = true;
    } catch (error, stack) {
      await runtime._recordStepEvent(
        WorkflowStepEventType.failed,
        runState,
        name,
        iteration: iteration,
        error: error.toString(),
      );
      Error.throwWithStackTrace(error, stack);
    }

    final control = stepContext.takeControl();
    if (control != null) {
      if (control.type != _ScriptControlType.continueRun) {
        await _suspend(control, name, iteration);
        throw const _WorkflowScriptSuspended();
      }
    }
    if (suspendedBySignal) {
      throw StateError(
        'Script checkpoint "$name" threw WorkflowSuspensionSignal without '
        'scheduling a suspension control.',
      );
    }

    final storedResult = declaredCheckpoint?.encodeValue(result) ?? result;
    await runtime._store.saveStep(runId, checkpointName, storedResult);
    await runtime._extendLeases(taskContext, runId);
    await runtime._recordStepEvent(
      WorkflowStepEventType.completed,
      runState,
      name,
      iteration: iteration,
      result: storedResult,
    );
    if (autoVersion) {
      _completedIterations[name] = iteration + 1;
    } else {
      _completedIterations[name] = 1;
    }
    _previousResult = result;
    _stepIndex += 1;
    return result;
  }

  /// Computes the next iteration for an auto-versioned checkpoint.
  int _nextIteration(String name) {
    final completed = _completedIterations[name] ?? 0;
    if (_suspensionStep == name && _suspensionIteration != null) {
      return _suspensionIteration!;
    }
    return completed;
  }

  /// Returns resume payload if it matches the current checkpoint/iteration.
  Object? _takeResumePayload(String stepName, int? iteration) {
    final matchesStep = _suspensionStep == stepName;
    if (!matchesStep) return null;
    if (iteration != null && _suspensionIteration != null) {
      if (_suspensionIteration != iteration) {
        return null;
      }
    }
    final payload = _resumePayload;
    _resumePayload = null;
    _suspensionStep = null;
    _suspensionIteration = null;
    return payload;
  }

  /// Persists suspension metadata and registers watchers/alarms.
  Future<void> _suspend(
    _ScriptControl control,
    String stepName,
    int iteration,
  ) async {
    if (control.type == _ScriptControlType.continueRun) {
      return;
    }
    final metadata = <String, Object?>{
      'step': stepName,
      'iteration': iteration,
      'iterationStep': stepName,
    };
    if (control.data != null && control.data!.isNotEmpty) {
      metadata.addAll(control.data!);
    }
    final now = clock.now();
    metadata['suspendedAt'] = now.toIso8601String();
    DateTime? policyDeadline;
    final suspendLimit = policy?.maxSuspendDuration;
    if (suspendLimit != null) {
      policyDeadline = now.add(suspendLimit);
      metadata['policyDeadline'] = policyDeadline.toIso8601String();
    }
    if (control.type == _ScriptControlType.sleep) {
      final requestedResumeAt = now.add(control.delay!);
      var resumeAt = requestedResumeAt;
      metadata['type'] = 'sleep';
      metadata['requestedResumeAt'] = requestedResumeAt.toIso8601String();
      if (policyDeadline != null && policyDeadline.isBefore(resumeAt)) {
        resumeAt = policyDeadline;
        metadata['policyDeadlineApplied'] = true;
      }
      metadata['resumeAt'] = resumeAt.toIso8601String();
      metadata.putIfAbsent('payload', () => true);
      await runtime._store.suspendUntil(
        runId,
        stepName,
        resumeAt,
        data: metadata,
      );
      await runtime._signals.workflowRunSuspended(
        WorkflowRunPayload(
          runId: runId,
          workflow: workflow,
          status: WorkflowRunStatus.suspended,
          step: stepName,
          metadata: {'type': 'sleep', 'resumeAt': resumeAt.toIso8601String()},
        ),
      );
      stemLogger.debug(
        'Workflow {workflow} suspended',
        runtime._runtimeLogContext(
          workflow: workflow,
          runId: runId,
          step: stepName,
          extra: {
            'workflowSuspensionType': 'sleep',
            'resumeAt': resumeAt.toIso8601String(),
            'workflowIteration': iteration,
            'runtimeId': runtime._runtimeId,
          },
        ),
      );
    } else if (control.type == _ScriptControlType.waitForEvent) {
      metadata['type'] = 'event';
      metadata['topic'] = control.topic;
      var deadline = control.deadline;
      if (deadline != null) {
        metadata['deadline'] = deadline.toIso8601String();
      }
      if (policyDeadline != null) {
        if (deadline == null || policyDeadline.isBefore(deadline)) {
          deadline = policyDeadline;
          metadata['policyDeadlineApplied'] = true;
        }
      }
      await runtime._store.registerWatcher(
        runId,
        stepName,
        control.topic!,
        deadline: deadline,
        data: metadata,
      );
      await runtime._signals.workflowRunSuspended(
        WorkflowRunPayload(
          runId: runId,
          workflow: workflow,
          status: WorkflowRunStatus.suspended,
          step: stepName,
          metadata: {
            'type': 'waitForEvent',
            'topic': control.topic,
            if (deadline != null) 'deadline': deadline.toIso8601String(),
          },
        ),
      );
      stemLogger.debug(
        'Workflow {workflow} suspended',
        runtime._runtimeLogContext(
          workflow: workflow,
          runId: runId,
          step: stepName,
          extra: {
            'workflowSuspensionType': 'event',
            'topic': control.topic!,
            'workflowIteration': iteration,
            if (deadline != null) 'deadline': deadline.toIso8601String(),
            'runtimeId': runtime._runtimeId,
          },
        ),
      );
    }
    _wasSuspended = true;
  }

  /// Previously completed checkpoint result, if any.
  Object? get previousResult => _previousResult;

  /// Builds a stable idempotency key for a checkpoint/iteration scope.
  String idempotencyKey(String stepName, int iteration, [String? scope]) {
    final defaultScope = iteration > 0 ? '$stepName#$iteration' : stepName;
    final effectiveScope = (scope == null || scope.isEmpty)
        ? defaultScope
        : scope;
    return '$workflow/$runId/$effectiveScope';
  }
}

/// Workflow script checkpoint context used by script-defined workflows.
class _WorkflowScriptStepContextImpl implements WorkflowScriptStepContext {
  _WorkflowScriptStepContextImpl({
    required this.execution,
    required String stepName,
    required int stepIndex,
    required int iteration,
    Object? resumeData,
    this.enqueuer,
    this.workflows,
  }) : _stepName = stepName,
       _stepIndex = stepIndex,
       _iteration = iteration,
       _resumeData = resumeData;

  final _WorkflowScriptExecution execution;
  final String _stepName;
  final int _stepIndex;
  final int _iteration;
  _ScriptControl? _control;
  Object? _resumeData;

  /// Consumes any control signal emitted by the step.
  _ScriptControl? takeControl() {
    final value = _control;
    _control = null;
    return value;
  }

  @override
  Future<void> awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    /// Suspends the run until an external event arrives.
    _control = _ScriptControl.waitForEvent(
      topic,
      deadline,
      data == null ? null : Map<String, Object?>.from(data),
    );
  }

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

  @override
  /// Suspends the run until the sleep duration elapses.
  Future<void> sleep(Duration duration, {Map<String, Object?>? data}) async {
    final resume = _resumeData;
    if (resume is Map<String, Object?>) {
      final type = resume['type'];
      final resumeAtRaw = resume['resumeAt'];
      if (type == 'sleep' && resumeAtRaw is String) {
        final resumeAt = DateTime.tryParse(resumeAtRaw);
        if (resumeAt != null && !resumeAt.isAfter(execution.clock.now())) {
          _control = const _ScriptControl.continueRun();
          return;
        }
      }
    }
    _control = _ScriptControl.sleep(
      duration,
      data == null ? null : Map<String, Object?>.from(data),
    );
  }

  @override
  String idempotencyKey([String? scope]) =>
      execution.idempotencyKey(_stepName, _iteration, scope);

  @override
  Map<String, Object?> get params => execution.params;

  @override
  Object? get previousResult => execution.previousResult;

  @override
  /// Returns and clears any resume payload supplied to this step.
  Object? takeResumeData() {
    final value = _resumeData;
    _resumeData = null;
    return value;
  }

  @override
  String get runId => execution.runId;

  @override
  int get stepIndex => _stepIndex;

  @override
  String get stepName => _stepName;

  @override
  int get iteration => _iteration;

  @override
  final TaskEnqueuer? enqueuer;

  @override
  final WorkflowCaller? workflows;

  @override
  String get workflow => execution.workflow;

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
      throw StateError('WorkflowScriptStepContext has no enqueuer configured');
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

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = enqueuer;
    if (delegate == null) {
      throw StateError('WorkflowScriptStepContext has no enqueuer configured');
    }
    return delegate.enqueueCall(call, enqueueOptions: enqueueOptions);
  }

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
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) async {
    final caller = workflows;
    if (caller == null) {
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.startWorkflowCall(call);
  }

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
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.waitForWorkflowRef(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

/// Enqueuer that prefixes workflow step metadata onto spawned tasks.
class _WorkflowStepEnqueuer implements TaskEnqueuer {
  _WorkflowStepEnqueuer({
    required this.delegate,
    required this.baseMeta,
    required this.executionQueue,
  });

  final TaskEnqueuer delegate;
  final Map<String, Object?> baseMeta;
  final String executionQueue;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    /// Merges workflow metadata into task enqueue requests.
    final mergedMeta = Map<String, Object?>.from(baseMeta)..addAll(meta);
    final resolvedOptions =
        (options.queue == 'default' && executionQueue != 'default')
        ? options.copyWith(queue: executionQueue)
        : options;
    return delegate.enqueue(
      name,
      args: args,
      headers: headers,
      options: resolvedOptions,
      notBefore: notBefore,
      meta: mergedMeta,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    final mergedMeta = Map<String, Object?>.from(baseMeta)..addAll(call.meta);
    TaskOptions? resolvedOptions = call.options;
    if (resolvedOptions == null) {
      final inherited = call.definition.defaultOptions;
      if (inherited.queue == 'default' && executionQueue != 'default') {
        resolvedOptions = inherited.copyWith(queue: executionQueue);
      }
    } else if (resolvedOptions.queue == 'default' &&
        executionQueue != 'default') {
      resolvedOptions = resolvedOptions.copyWith(queue: executionQueue);
    }
    final mergedCall = call.copyWith(
      options: resolvedOptions,
      meta: Map.unmodifiable(mergedMeta),
    );
    return delegate.enqueueCall(
      mergedCall,
      enqueueOptions: enqueueOptions,
    );
  }
}

class _ChildWorkflowCaller implements WorkflowCaller {
  const _ChildWorkflowCaller({
    required this.runtime,
    required this.parentRunId,
  });

  final WorkflowRuntime runtime;
  final String parentRunId;

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return runtime.startWorkflowRef(
      definition,
      params,
      parentRunId: this.parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return runtime.startWorkflowCall(
      call.copyWith(parentRunId: parentRunId),
    );
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return _waitForChildWorkflow(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  Future<WorkflowResult<TResult>?>
  _waitForChildWorkflow<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    required Duration pollInterval,
    required Duration? timeout,
  }) async {
    final startedAt = runtime.clock.now();
    while (true) {
      final state = await runtime._store.get(runId);
      if (state == null) {
        return null;
      }
      if (state.isTerminal) {
        return runtime._buildResult(
          state,
          definition.decode,
          timedOut: false,
        );
      }
      if (timeout != null &&
          runtime.clock.now().difference(startedAt) >= timeout) {
        return runtime._buildResult(
          state,
          definition.decode,
          timedOut: true,
        );
      }
      await runtime.executeRun(runId);
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
    }
  }
}

Map<String, Object?> _coerceEventPayload(String topic, Object? payload) {
  if (payload is Map<String, Object?>) {
    return Map<String, Object?>.from(payload);
  }
  if (payload is Map) {
    final encoded = <String, Object?>{};
    for (final MapEntry(key: key, value: value) in payload.entries) {
      if (key is! String) {
        throw ArgumentError.value(
          payload,
          'payload',
          'Workflow event payloads for topic "$topic" must use String keys.',
        );
      }
      encoded[key] = value;
    }
    return encoded;
  }
  throw ArgumentError.value(
    payload,
    'payload',
    'Workflow event payloads for topic "$topic" must encode to '
        'Map<String, Object?>.',
  );
}

class _WorkflowScriptSuspended implements Exception {
  const _WorkflowScriptSuspended();
}

class _WorkflowLeaseLost implements Exception {
  const _WorkflowLeaseLost();
}

enum _ScriptControlType { continueRun, sleep, waitForEvent }

class _ScriptControl {
  const _ScriptControl.sleep(this.delay, this.data)
    : type = _ScriptControlType.sleep,
      topic = null,
      deadline = null;

  const _ScriptControl.waitForEvent(this.topic, this.deadline, this.data)
    : type = _ScriptControlType.waitForEvent,
      delay = null;

  const _ScriptControl.continueRun()
    : type = _ScriptControlType.continueRun,
      delay = null,
      topic = null,
      deadline = null,
      data = null;

  final _ScriptControlType type;
  final Duration? delay;
  final String? topic;
  final DateTime? deadline;
  final Map<String, Object?>? data;
}
