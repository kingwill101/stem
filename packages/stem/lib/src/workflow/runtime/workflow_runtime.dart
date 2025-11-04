import 'dart:async';

import 'package:stem/src/core/task_invocation.dart';

import '../../core/contracts.dart';
import '../../core/stem.dart';
import '../../signals/emitter.dart';
import '../../signals/payloads.dart';
import '../core/event_bus.dart';
import '../core/flow_context.dart';
import '../core/flow_step.dart';
import '../core/workflow_cancellation_policy.dart';
import '../core/workflow_definition.dart';
import '../core/workflow_script_context.dart';
import '../core/run_state.dart';
import '../core/workflow_status.dart';
import '../core/workflow_store.dart';
import 'workflow_registry.dart';

const String workflowRunTaskName = 'stem.workflow.run';

/// Coordinates execution of workflow runs by dequeuing tasks, invoking steps,
/// and persisting progress via a [WorkflowStore].
///
/// The runtime is durable: each step is re-executed from the top after a
/// suspension or worker crash. Handlers must therefore be idempotent and rely
/// on persisted step outputs or resume payloads to detect prior progress.
class WorkflowRuntime {
  WorkflowRuntime({
    required Stem stem,
    required WorkflowStore store,
    required EventBus eventBus,
    Duration pollInterval = const Duration(milliseconds: 500),
    this.leaseExtension = const Duration(seconds: 30),
    this.queue = 'workflow',
  }) : _stem = stem,
       _store = store,
       _eventBus = eventBus,
       _pollInterval = pollInterval;

  final Stem _stem;
  final WorkflowStore _store;
  final EventBus _eventBus;
  final Duration _pollInterval;
  final Duration leaseExtension;
  final WorkflowRegistry _registry = WorkflowRegistry();
  final String queue;
  final StemSignalEmitter _signals = StemSignalEmitter(
    defaultSender: 'workflow',
  );

  Timer? _timer;
  bool _started = false;

  WorkflowRegistry get registry => _registry;

  /// Registers a workflow definition so it can be scheduled via
  /// [startWorkflow]. Typically invoked by `StemWorkflowApp` during startup.
  void registerWorkflow(WorkflowDefinition definition) {
    _registry.register(definition);
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
    final runId = await _store.createRun(
      workflow: name,
      params: params,
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
    await _enqueueRun(runId);
    return runId;
  }

  /// Emits an external event and resumes all runs waiting on [topic].
  ///
  /// Each resumed run receives the event as `resumeData` for the awaiting step
  /// before being re-enqueued.
  Future<void> emit(String topic, Map<String, Object?> payload) async {
    await _eventBus.emit(topic, payload);
    final runIds = await _store.runsWaitingOn(topic);
    for (final runId in runIds) {
      final state = await _store.get(runId);
      if (state == null) {
        continue;
      }
      final now = DateTime.now();
      if (await _maybeCancelForPolicy(state, now: now)) {
        continue;
      }
      final metadata = <String, Object?>{};
      final existing = state.suspensionData;
      if (existing != null && existing.isNotEmpty) {
        metadata.addAll(existing);
      }
      metadata['type'] = 'event';
      metadata['topic'] = topic;
      metadata['payload'] = payload;
      await _store.markResumed(runId, data: metadata);
      await _enqueueRun(runId);
    }
  }

  /// Starts periodic polling that resumes runs whose wake-up time has elapsed.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(_pollInterval, (_) async {
      final now = DateTime.now();
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
        await _enqueueRun(runId);
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
    final now = DateTime.now();
    if (await _maybeCancelForPolicy(runState, now: now)) {
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
      return;
    }

    final wasSuspended = runState.status == WorkflowStatus.suspended;
    await _store.markRunning(runId);
    if (wasSuspended) {
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
        previousResult = await _store.readStep(runId, checkpoint);
      }
    }
    Object? resumeData = suspensionData?['payload'];

    while (cursor < definition.steps.length) {
      if (policy != null && policy.maxRunDuration != null) {
        final elapsed = DateTime.now().difference(runState.createdAt);
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
          ? _currentIterationForStep(step, completedIterations, suspensionData)
          : 0;
      final checkpointName = step.autoVersion
          ? _versionedName(step.name, iteration)
          : step.name;

      await _store.markRunning(runId, stepName: step.name);
      await _extendLease(taskContext);
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
        previousResult = cached;
        cursor += 1;
        await _extendLease(taskContext);
        continue;
      }

      final context = FlowContext(
        workflow: runState.workflow,
        runId: runId,
        stepName: step.name,
        params: runState.params,
        previousResult: previousResult,
        stepIndex: cursor,
        iteration: iteration,
        resumeData: resumeData,
      );
      resumeData = null;
      dynamic result;
      try {
        result = await step.handler(context);
      } catch (error, stack) {
        await _store.markFailed(runId, error, stack, terminal: false);
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
      if (control != null) {
        final metadata = <String, Object?>{
          'step': step.name,
          'iteration': iteration,
          'iterationStep': step.name,
        };
        final suspendedAt = DateTime.now();
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
          await _store.suspendUntil(runId, step.name, resumeAt, data: metadata);
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
        } else if (control.type == FlowControlType.waitForEvent) {
          metadata['type'] = 'event';
          metadata['topic'] = control.topic;
          DateTime? deadline = control.deadline;
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
          await _store.suspendOnTopic(
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
        }
        return;
      }

      await _store.saveStep(runId, checkpointName, result);
      await _extendLease(taskContext);
      if (step.autoVersion) {
        completedIterations[step.name] = iteration + 1;
      } else {
        completedIterations[step.name] = 1;
      }
      previousResult = result;
      cursor += 1;
    }

    await _store.markCompleted(runId, previousResult);
    await _extendLease(taskContext);
    await _signals.workflowRunCompleted(
      WorkflowRunPayload(
        runId: runId,
        workflow: runState.workflow,
        status: WorkflowRunStatus.completed,
        metadata: {'result': previousResult},
      ),
    );
  }

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
      await _signals.workflowRunResumed(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.running,
        ),
      );
    }
    final steps = await _store.listSteps(runId);
    final completedIterations = await _loadCompletedIterations(runId);
    Object? previousResult;
    if (steps.isNotEmpty) {
      previousResult = steps.last.value;
    }
    final execution = _WorkflowScriptExecution(
      runtime: this,
      runState: runState,
      taskContext: taskContext,
      completedIterations: completedIterations,
      previousResult: previousResult,
      initialStepIndex: steps.length,
      suspensionData: runState.suspensionData,
      policy: runState.cancellationPolicy,
    );

    try {
      final result = await script(execution);
      if (execution.wasSuspended) {
        return;
      }
      await _store.markCompleted(runId, result);
      await _extendLease(taskContext);
      await _signals.workflowRunCompleted(
        WorkflowRunPayload(
          runId: runId,
          workflow: runState.workflow,
          status: WorkflowRunStatus.completed,
          metadata: {'result': result},
        ),
      );
    } on _WorkflowScriptSuspended {
      return;
    } catch (error, stack) {
      await _store.markFailed(runId, error, stack, terminal: false);
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

  Future<Map<String, int>> _loadCompletedIterations(String runId) async {
    final entries = await _store.listSteps(runId);
    final counts = <String, int>{};
    for (final entry in entries) {
      final base = _baseStepName(entry.name);
      final suffix = _parseIterationSuffix(entry.name);
      final nextIndex = suffix != null ? suffix + 1 : 1;
      final current = counts[base] ?? 0;
      if (nextIndex > current) counts[base] = nextIndex;
    }
    return counts;
  }

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

  int? _parseIterationSuffix(String name) {
    final hashIndex = name.lastIndexOf('#');
    if (hashIndex == -1) return null;
    final suffix = name.substring(hashIndex + 1);
    return int.tryParse(suffix);
  }

  String _baseStepName(String name) {
    final hashIndex = name.indexOf('#');
    if (hashIndex == -1) return name;
    return name.substring(0, hashIndex);
  }

  Future<void> _extendLease(TaskContext? context) async {
    if (context == null) return;
    if (leaseExtension.inMicroseconds <= 0) return;
    try {
      await context.extendLease(leaseExtension);
    } catch (_) {
      // Ignore lease extension failures; broker will fall back to default TTL.
    }
  }

  Future<void> _enqueueRun(String runId) async {
    await _stem.enqueue(
      workflowRunTaskName,
      args: {'runId': runId},
      options: TaskOptions(queue: queue),
    );
  }

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

  Future<void> _cancelForPolicy(
    RunState state, {
    required String reason,
    required Map<String, Object?> metadata,
  }) async {
    await _store.cancel(state.id, reason: reason);
    final payloadMetadata = <String, Object?>{
      'policy': reason,
      'cancelledAt': DateTime.now().toIso8601String(),
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
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final runId = args['runId'] as String?;
    if (runId == null) {
      throw ArgumentError('workflow.run missing runId');
    }
    await runtime.executeRun(runId, taskContext: context);
  }
}

class _WorkflowScriptExecution implements WorkflowScriptContext {
  _WorkflowScriptExecution({
    required this.runtime,
    required this.runState,
    required this.taskContext,
    required Map<String, int> completedIterations,
    required Object? previousResult,
    required int initialStepIndex,
    Map<String, Object?>? suspensionData,
    required this.policy,
  }) : _completedIterations = Map<String, int>.from(completedIterations),
       _previousResult = previousResult,
       _stepIndex = initialStepIndex,
       _resumePayload = suspensionData?['payload'],
       _suspensionStep =
           (suspensionData?['iterationStep'] ?? suspensionData?['step'])
               as String?,
       _suspensionIteration = suspensionData?['iteration'] as int?;

  final WorkflowRuntime runtime;
  final RunState runState;
  final TaskContext? taskContext;
  final Map<String, int> _completedIterations;
  final WorkflowCancellationPolicy? policy;
  Object? _previousResult;
  int _stepIndex;
  bool _wasSuspended = false;
  String? _lastStepName;
  String? _suspensionStep;
  int? _suspensionIteration;
  Object? _resumePayload;

  bool get wasSuspended => _wasSuspended;
  String? get lastStepName => _lastStepName;

  @override
  Map<String, Object?> get params => runState.params;

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
    _lastStepName = name;
    final policy = this.policy;
    if (policy != null && policy.maxRunDuration != null) {
      final elapsed = DateTime.now().difference(runState.createdAt);
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

    await runtime._store.markRunning(runId, stepName: name);
    await runtime._extendLease(taskContext);
    await runtime._signals.workflowRunResumed(
      WorkflowRunPayload(
        runId: runId,
        workflow: workflow,
        status: WorkflowRunStatus.running,
        step: name,
      ),
    );

    final cached = await runtime._store.readStep<Object?>(
      runId,
      checkpointName,
    );
    if (cached != null) {
      _previousResult = cached;
      if (autoVersion) {
        _completedIterations[name] = iteration + 1;
      } else {
        _completedIterations[name] = 1;
      }
      _stepIndex += 1;
      await runtime._extendLease(taskContext);
      return cached as T;
    }

    final resumeData = _takeResumePayload(name, autoVersion ? iteration : null);
    final stepContext = _WorkflowScriptStepContextImpl(
      execution: this,
      stepName: name,
      stepIndex: _stepIndex,
      iteration: iteration,
      resumeData: resumeData,
    );

    final result = await handler(stepContext);

    final control = stepContext.takeControl();
    if (control != null) {
      await _suspend(control, name, iteration);
      throw const _WorkflowScriptSuspended();
    }

    await runtime._store.saveStep(runId, checkpointName, result);
    await runtime._extendLease(taskContext);
    if (autoVersion) {
      _completedIterations[name] = iteration + 1;
    } else {
      _completedIterations[name] = 1;
    }
    _previousResult = result;
    _stepIndex += 1;
    return result;
  }

  int _nextIteration(String name) {
    final completed = _completedIterations[name] ?? 0;
    if (_suspensionStep == name && _suspensionIteration != null) {
      return _suspensionIteration!;
    }
    return completed;
  }

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

  Future<void> _suspend(
    _ScriptControl control,
    String stepName,
    int iteration,
  ) async {
    final metadata = <String, Object?>{
      'step': stepName,
      'iteration': iteration,
      'iterationStep': stepName,
    };
    if (control.data != null && control.data!.isNotEmpty) {
      metadata.addAll(control.data!);
    }
    final now = DateTime.now();
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
    } else if (control.type == _ScriptControlType.waitForEvent) {
      metadata['type'] = 'event';
      metadata['topic'] = control.topic;
      DateTime? deadline = control.deadline;
      if (deadline != null) {
        metadata['deadline'] = deadline.toIso8601String();
      }
      if (policyDeadline != null) {
        if (deadline == null || policyDeadline.isBefore(deadline)) {
          deadline = policyDeadline;
          metadata['policyDeadlineApplied'] = true;
        }
      }
      await runtime._store.suspendOnTopic(
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
    }
    _wasSuspended = true;
  }

  Object? get previousResult => _previousResult;

  String idempotencyKey(String stepName, int iteration, [String? scope]) {
    final defaultScope = iteration > 0 ? '$stepName#$iteration' : stepName;
    final effectiveScope = (scope == null || scope.isEmpty)
        ? defaultScope
        : scope;
    return '$workflow/$runId/$effectiveScope';
  }
}

class _WorkflowScriptStepContextImpl implements WorkflowScriptStepContext {
  _WorkflowScriptStepContextImpl({
    required this.execution,
    required String stepName,
    required int stepIndex,
    required int iteration,
    Object? resumeData,
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
    _control = _ScriptControl.waitForEvent(
      topic,
      deadline,
      data == null ? null : Map<String, Object?>.from(data),
    );
  }

  @override
  Future<void> sleep(Duration duration, {Map<String, Object?>? data}) async {
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
  String get workflow => execution.workflow;
}

class _WorkflowScriptSuspended implements Exception {
  const _WorkflowScriptSuspended();
}

enum _ScriptControlType { sleep, waitForEvent }

class _ScriptControl {
  const _ScriptControl.sleep(this.delay, this.data)
    : type = _ScriptControlType.sleep,
      topic = null,
      deadline = null;

  const _ScriptControl.waitForEvent(this.topic, this.deadline, this.data)
    : type = _ScriptControlType.waitForEvent,
      delay = null;

  final _ScriptControlType type;
  final Duration? delay;
  final String? topic;
  final DateTime? deadline;
  final Map<String, Object?>? data;
}
