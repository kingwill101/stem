import 'dart:async';

import 'package:stem/src/core/task_invocation.dart';

import '../../core/contracts.dart';
import '../../core/stem.dart';
import '../../signals/emitter.dart';
import '../../signals/payloads.dart';
import '../core/event_bus.dart';
import '../core/flow_context.dart';
import '../core/flow_step.dart';
import '../core/workflow_definition.dart';
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
      final metadata = <String, Object?>{};
      final existing = state?.suspensionData;
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
      final due = await _store.dueRuns(DateTime.now());
      for (final runId in due) {
        final state = await _store.get(runId);
        await _store.markResumed(runId, data: state?.suspensionData);
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
        if (control.type == FlowControlType.sleep) {
          final resumeAt = DateTime.now().add(control.delay!);
          metadata['type'] = 'sleep';
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
          if (control.deadline != null) {
            metadata['deadline'] = control.deadline!.toIso8601String();
          }
          final controlData = control.data;
          if (controlData != null && controlData.isNotEmpty) {
            metadata.addAll(controlData);
          }
          await _store.suspendOnTopic(
            runId,
            step.name,
            control.topic!,
            deadline: control.deadline,
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
                if (control.deadline != null)
                  'deadline': control.deadline!.toIso8601String(),
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
