import 'package:contextual/contextual.dart';

import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:stem/src/signals/signal.dart';

/// Function signature for reporting signal errors.
typedef SignalErrorReporter =
    void Function(String signalName, Object error, StackTrace stackTrace);

/// Configuration for controlling Stem signals behavior.
class StemSignalConfiguration {
  /// Creates a new [StemSignalConfiguration] instance.
  const StemSignalConfiguration({
    this.enabled = true,
    Map<String, bool>? enabledSignals,
  }) : enabledSignals = enabledSignals ?? const {};

  /// Whether signals are globally enabled.
  final bool enabled;

  /// Map of specific signal names to their enabled state.
  final Map<String, bool> enabledSignals;

  /// Checks if a signal with the given [name] is enabled.
  bool isEnabled(String name) => enabled && (enabledSignals[name] ?? true);

  /// Creates a copy of this configuration with the given fields replaced.
  StemSignalConfiguration copyWith({
    bool? enabled,
    Map<String, bool>? enabledSignals,
  }) {
    return StemSignalConfiguration(
      enabled: enabled ?? this.enabled,
      enabledSignals: enabledSignals ?? this.enabledSignals,
    );
  }
}

/// Central registry for all Stem framework signals.
class StemSignals {
  /// Signal name constant for before task publish event.
  static const String beforeTaskPublishName = 'before-task-publish';

  /// Signal name constant for after task publish event.
  static const String afterTaskPublishName = 'after-task-publish';

  /// Signal name constant for task received event.
  static const String taskReceivedName = 'task-received';

  /// Signal name constant for task prerun event.
  static const String taskPrerunName = 'task-prerun';

  /// Signal name constant for task postrun event.
  static const String taskPostrunName = 'task-postrun';

  /// Signal name constant for task retry event.
  static const String taskRetryName = 'task-retry';

  /// Signal name constant for task succeeded event.
  static const String taskSucceededName = 'task-succeeded';

  /// Signal name constant for task failed event.
  static const String taskFailedName = 'task-failed';

  /// Signal name constant for task revoked event.
  static const String taskRevokedName = 'task-revoked';

  /// Signal name constant for worker init event.
  static const String workerInitName = 'worker-init';

  /// Signal name constant for worker ready event.
  static const String workerReadyName = 'worker-ready';

  /// Signal name constant for worker stopping event.
  static const String workerStoppingName = 'worker-stopping';

  /// Signal name constant for worker shutdown event.
  static const String workerShutdownName = 'worker-shutdown';

  /// Signal name constant for worker heartbeat event.
  static const String workerHeartbeatName = 'worker-heartbeat';

  /// Signal name constant for worker child init event.
  static const String workerChildInitName = 'worker-child-init';

  /// Signal name constant for worker child shutdown event.
  static const String workerChildShutdownName = 'worker-child-shutdown';

  /// Signal name constant for schedule entry due event.
  static const String scheduleEntryDueName = 'schedule-entry-due';

  /// Signal name constant for schedule entry dispatched event.
  static const String scheduleEntryDispatchedName = 'schedule-entry-dispatched';

  /// Signal name constant for schedule entry failed event.
  static const String scheduleEntryFailedName = 'schedule-entry-failed';

  /// Signal name constant for control command received event.
  static const String controlCommandReceivedName = 'control-command-received';

  /// Signal name constant for control command completed event.
  static const String controlCommandCompletedName = 'control-command-completed';

  /// Signal name constant for workflow run started event.
  static const String workflowRunStartedName = 'workflow-run-started';

  /// Signal name constant for workflow run suspended event.
  static const String workflowRunSuspendedName = 'workflow-run-suspended';

  /// Signal name constant for workflow run resumed event.
  static const String workflowRunResumedName = 'workflow-run-resumed';

  /// Signal name constant for workflow run completed event.
  static const String workflowRunCompletedName = 'workflow-run-completed';

  /// Signal name constant for workflow run failed event.
  static const String workflowRunFailedName = 'workflow-run-failed';

  /// Signal name constant for workflow run cancelled event.
  static const String workflowRunCancelledName = 'workflow-run-cancelled';

  /// Current signal configuration.
  static StemSignalConfiguration _configuration =
      const StemSignalConfiguration();

  /// Error reporter callback.
  static SignalErrorReporter? _errorReporter;

  /// Signal emitted before a task is published to the broker.
  static final Signal<BeforeTaskPublishPayload> beforeTaskPublish =
      Signal<BeforeTaskPublishPayload>(
        name: beforeTaskPublishName,
        config: _dispatchConfigFor(beforeTaskPublishName),
      );

  /// Signal emitted after a task has been published to the broker.
  static final Signal<AfterTaskPublishPayload> afterTaskPublish =
      Signal<AfterTaskPublishPayload>(
        name: afterTaskPublishName,
        config: _dispatchConfigFor(afterTaskPublishName),
      );

  /// Signal emitted when a task is received by a worker.
  static final Signal<TaskReceivedPayload> taskReceived =
      Signal<TaskReceivedPayload>(
        name: taskReceivedName,
        config: _dispatchConfigFor(taskReceivedName),
      );

  /// Signal emitted before a task begins execution.
  static final Signal<TaskPrerunPayload> taskPrerun = Signal<TaskPrerunPayload>(
    name: taskPrerunName,
    config: _dispatchConfigFor(taskPrerunName),
  );

  /// Signal emitted after a task finishes execution.
  static final Signal<TaskPostrunPayload> taskPostrun =
      Signal<TaskPostrunPayload>(
        name: taskPostrunName,
        config: _dispatchConfigFor(taskPostrunName),
      );

  /// Signal emitted when a task is scheduled for retry.
  static final Signal<TaskRetryPayload> taskRetry = Signal<TaskRetryPayload>(
    name: taskRetryName,
    config: _dispatchConfigFor(taskRetryName),
  );

  /// Signal emitted when a task completes successfully.
  static final Signal<TaskSuccessPayload> taskSucceeded =
      Signal<TaskSuccessPayload>(
        name: taskSucceededName,
        config: _dispatchConfigFor(taskSucceededName),
      );

  /// Signal emitted when a task fails.
  static final Signal<TaskFailurePayload> taskFailed =
      Signal<TaskFailurePayload>(
        name: taskFailedName,
        config: _dispatchConfigFor(taskFailedName),
      );

  /// Signal emitted when a task is revoked.
  static final Signal<TaskRevokedPayload> taskRevoked =
      Signal<TaskRevokedPayload>(
        name: taskRevokedName,
        config: _dispatchConfigFor(taskRevokedName),
      );

  /// Signal emitted when a worker initializes.
  static final Signal<WorkerLifecyclePayload> workerInit =
      Signal<WorkerLifecyclePayload>(
        name: workerInitName,
        config: _dispatchConfigFor(workerInitName),
      );

  /// Signal emitted when a worker is ready to accept tasks.
  static final Signal<WorkerLifecyclePayload> workerReady =
      Signal<WorkerLifecyclePayload>(
        name: workerReadyName,
        config: _dispatchConfigFor(workerReadyName),
      );

  /// Signal emitted when a worker is stopping.
  static final Signal<WorkerLifecyclePayload> workerStopping =
      Signal<WorkerLifecyclePayload>(
        name: workerStoppingName,
        config: _dispatchConfigFor(workerStoppingName),
      );

  /// Signal emitted when a worker has shut down.
  static final Signal<WorkerLifecyclePayload> workerShutdown =
      Signal<WorkerLifecyclePayload>(
        name: workerShutdownName,
        config: _dispatchConfigFor(workerShutdownName),
      );

  /// Signal emitted when a worker sends a heartbeat.
  static final Signal<WorkerHeartbeatPayload> workerHeartbeat =
      Signal<WorkerHeartbeatPayload>(
        name: workerHeartbeatName,
        config: _dispatchConfigFor(workerHeartbeatName),
      );

  /// Signal emitted when a worker child isolate initializes.
  static final Signal<WorkerChildLifecyclePayload> workerChildInit =
      Signal<WorkerChildLifecyclePayload>(
        name: workerChildInitName,
        config: _dispatchConfigFor(workerChildInitName),
      );

  /// Signal emitted when a worker child isolate shuts down.
  static final Signal<WorkerChildLifecyclePayload> workerChildShutdown =
      Signal<WorkerChildLifecyclePayload>(
        name: workerChildShutdownName,
        config: _dispatchConfigFor(workerChildShutdownName),
      );

  /// Signal emitted when a workflow run starts.
  static final Signal<WorkflowRunPayload> workflowRunStarted =
      Signal<WorkflowRunPayload>(
        name: workflowRunStartedName,
        config: _dispatchConfigFor(workflowRunStartedName),
      );

  /// Signal emitted when a workflow run is suspended.
  static final Signal<WorkflowRunPayload> workflowRunSuspended =
      Signal<WorkflowRunPayload>(
        name: workflowRunSuspendedName,
        config: _dispatchConfigFor(workflowRunSuspendedName),
      );

  /// Signal emitted when a workflow run is resumed.
  static final Signal<WorkflowRunPayload> workflowRunResumed =
      Signal<WorkflowRunPayload>(
        name: workflowRunResumedName,
        config: _dispatchConfigFor(workflowRunResumedName),
      );

  /// Signal emitted when a workflow run completes.
  static final Signal<WorkflowRunPayload> workflowRunCompleted =
      Signal<WorkflowRunPayload>(
        name: workflowRunCompletedName,
        config: _dispatchConfigFor(workflowRunCompletedName),
      );

  /// Signal emitted when a workflow run fails.
  static final Signal<WorkflowRunPayload> workflowRunFailed =
      Signal<WorkflowRunPayload>(
        name: workflowRunFailedName,
        config: _dispatchConfigFor(workflowRunFailedName),
      );

  /// Signal emitted when a workflow run is cancelled.
  static final Signal<WorkflowRunPayload> workflowRunCancelled =
      Signal<WorkflowRunPayload>(
        name: workflowRunCancelledName,
        config: _dispatchConfigFor(workflowRunCancelledName),
      );

  /// Signal emitted when a schedule entry is due.
  static final Signal<ScheduleEntryDuePayload> scheduleEntryDue =
      Signal<ScheduleEntryDuePayload>(
        name: scheduleEntryDueName,
        config: _dispatchConfigFor(scheduleEntryDueName),
      );

  /// Signal emitted when a schedule entry has been dispatched.
  static final Signal<ScheduleEntryDispatchedPayload> scheduleEntryDispatched =
      Signal<ScheduleEntryDispatchedPayload>(
        name: scheduleEntryDispatchedName,
        config: _dispatchConfigFor(scheduleEntryDispatchedName),
      );

  /// Signal emitted when a schedule entry fails to execute.
  static final Signal<ScheduleEntryFailedPayload> scheduleEntryFailed =
      Signal<ScheduleEntryFailedPayload>(
        name: scheduleEntryFailedName,
        config: _dispatchConfigFor(scheduleEntryFailedName),
      );

  /// Signal emitted when a control command is received.
  static final Signal<ControlCommandReceivedPayload> controlCommandReceived =
      Signal<ControlCommandReceivedPayload>(
        name: controlCommandReceivedName,
        config: _dispatchConfigFor(controlCommandReceivedName),
      );

  /// Signal emitted when a control command completes.
  static final Signal<ControlCommandCompletedPayload> controlCommandCompleted =
      Signal<ControlCommandCompletedPayload>(
        name: controlCommandCompletedName,
        config: _dispatchConfigFor(controlCommandCompletedName),
      );

  static final List<Signal<dynamic>> _allSignals = <Signal<dynamic>>[
    beforeTaskPublish,
    afterTaskPublish,
    taskReceived,
    taskPrerun,
    taskPostrun,
    taskRetry,
    taskSucceeded,
    taskFailed,
    taskRevoked,
    workerInit,
    workerReady,
    workerStopping,
    workerShutdown,
    workerHeartbeat,
    workerChildInit,
    workerChildShutdown,
    scheduleEntryDue,
    scheduleEntryDispatched,
    scheduleEntryFailed,
    controlCommandReceived,
    controlCommandCompleted,
  ];

  /// Configures the global signal behavior.
  static void configure({
    StemSignalConfiguration? configuration,
    SignalErrorReporter? onError,
  }) {
    if (configuration != null) {
      _configuration = configuration;
    }
    _errorReporter = onError;
    _applyConfiguration();
  }

  /// Applies the current configuration to all signals.
  static void _applyConfiguration() {
    for (final signal in _allSignals) {
      signal.config = _dispatchConfigFor(signal.name);
    }
  }

  /// Subscribes to the before task publish signal with optional filtering.
  static SignalSubscription onBeforeTaskPublish(
    SignalHandler<BeforeTaskPublishPayload> handler, {
    String? taskName,
  }) {
    return beforeTaskPublish.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  /// Subscribes to the after task publish signal with optional filtering.
  static SignalSubscription onAfterTaskPublish(
    SignalHandler<AfterTaskPublishPayload> handler, {
    String? taskName,
  }) {
    return afterTaskPublish.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task prerun signal with optional filtering.
  static SignalSubscription onTaskPrerun(
    SignalHandler<TaskPrerunPayload> handler, {
    String? taskName,
  }) {
    return taskPrerun.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task postrun signal with optional filtering.
  static SignalSubscription onTaskPostrun(
    SignalHandler<TaskPostrunPayload> handler, {
    String? taskName,
  }) {
    return taskPostrun.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task success signal with optional filtering.
  static SignalSubscription onTaskSuccess(
    SignalHandler<TaskSuccessPayload> handler, {
    String? taskName,
  }) {
    return taskSucceeded.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task failure signal with optional filtering.
  static SignalSubscription onTaskFailure(
    SignalHandler<TaskFailurePayload> handler, {
    String? taskName,
  }) {
    return taskFailed.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task retry signal with optional filtering.
  static SignalSubscription onTaskRetry(
    SignalHandler<TaskRetryPayload> handler, {
    String? taskName,
  }) {
    return taskRetry.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task received signal with optional filtering.
  static SignalSubscription onTaskReceived(
    SignalHandler<TaskReceivedPayload> handler, {
    String? taskName,
  }) {
    return taskReceived.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the task revoked signal with optional filtering.
  static SignalSubscription onTaskRevoked(
    SignalHandler<TaskRevokedPayload> handler, {
    String? taskName,
  }) {
    return taskRevoked.connect(handler, filter: _taskNameFilter(taskName));
  }

  /// Subscribes to the worker heartbeat signal with optional filtering.
  static SignalSubscription onWorkerHeartbeat(
    SignalHandler<WorkerHeartbeatPayload> handler, {
    String? workerId,
  }) {
    return workerHeartbeat.connect(handler, filter: _workerIdFilter(workerId));
  }

  /// Subscribes to the worker child init signal with optional filtering.
  static SignalSubscription onWorkerChildInit(
    SignalHandler<WorkerChildLifecyclePayload> handler, {
    String? workerId,
  }) {
    return workerChildInit.connect(handler, filter: _workerIdFilter(workerId));
  }

  /// Subscribes to the worker child shutdown signal with optional filtering.
  static SignalSubscription onWorkerChildShutdown(
    SignalHandler<WorkerChildLifecyclePayload> handler, {
    String? workerId,
  }) {
    return workerChildShutdown.connect(
      handler,
      filter: _workerIdFilter(workerId),
    );
  }

  /// Subscribes to the schedule entry due signal with optional filtering.
  static SignalSubscription onScheduleEntryDue(
    SignalHandler<ScheduleEntryDuePayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryDue.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  /// Subscribes to the schedule entry dispatched signal with optional
  /// filtering.
  static SignalSubscription onScheduleEntryDispatched(
    SignalHandler<ScheduleEntryDispatchedPayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryDispatched.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  /// Subscribes to the schedule entry failed signal with optional filtering.
  static SignalSubscription onScheduleEntryFailed(
    SignalHandler<ScheduleEntryFailedPayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryFailed.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  /// Subscribes to the control command received signal with optional filtering.
  static SignalSubscription onControlCommandReceived(
    SignalHandler<ControlCommandReceivedPayload> handler, {
    String? commandType,
  }) {
    return controlCommandReceived.connect(
      handler,
      filter: _commandTypeFilter(commandType),
    );
  }

  /// Subscribes to the control command completed signal with optional
  /// filtering.
  static SignalSubscription onControlCommandCompleted(
    SignalHandler<ControlCommandCompletedPayload> handler, {
    String? commandType,
  }) {
    return controlCommandCompleted.connect(
      handler,
      filter: _commandTypeFilter(commandType),
    );
  }

  /// Subscribes to the worker ready signal with optional filtering.
  static SignalSubscription onWorkerReady(
    SignalHandler<WorkerLifecyclePayload> handler, {
    String? workerId,
  }) {
    return workerReady.connect(
      handler,
      filter: _workerIdFilter<WorkerLifecyclePayload>(workerId),
    );
  }

  static SignalFilter<T>? _taskNameFilter<T>(String? taskName) {
    if (taskName == null) return null;
    return SignalFilter<T>.where(
      (payload, _) => _payloadTaskName(payload as Object) == taskName,
    );
  }

  static String? _payloadTaskName(Object payload) {
    if (payload is BeforeTaskPublishPayload) return payload.envelope.name;
    if (payload is AfterTaskPublishPayload) return payload.envelope.name;
    if (payload is TaskReceivedPayload) return payload.envelope.name;
    if (payload is TaskPrerunPayload) return payload.envelope.name;
    if (payload is TaskPostrunPayload) return payload.envelope.name;
    if (payload is TaskRetryPayload) return payload.envelope.name;
    if (payload is TaskSuccessPayload) return payload.envelope.name;
    if (payload is TaskFailurePayload) return payload.envelope.name;
    if (payload is TaskRevokedPayload) return payload.envelope.name;
    return null;
  }

  static SignalFilter<T>? _workerIdFilter<T>(String? workerId) {
    if (workerId == null) return null;
    return SignalFilter<T>.where(
      (payload, _) => _payloadWorkerId(payload as Object) == workerId,
    );
  }

  static String? _payloadWorkerId(Object payload) {
    if (payload is TaskReceivedPayload) return payload.worker.id;
    if (payload is TaskPrerunPayload) return payload.worker.id;
    if (payload is TaskPostrunPayload) return payload.worker.id;
    if (payload is TaskRetryPayload) return payload.worker.id;
    if (payload is TaskSuccessPayload) return payload.worker.id;
    if (payload is TaskFailurePayload) return payload.worker.id;
    if (payload is TaskRevokedPayload) return payload.worker.id;
    if (payload is WorkerLifecyclePayload) return payload.worker.id;
    if (payload is WorkerHeartbeatPayload) return payload.worker.id;
    if (payload is WorkerChildLifecyclePayload) return payload.worker.id;
    if (payload is ControlCommandReceivedPayload) return payload.worker.id;
    if (payload is ControlCommandCompletedPayload) return payload.worker.id;
    return null;
  }

  static SignalFilter<T>? _scheduleIdFilter<T>(String? entryId) {
    if (entryId == null) return null;
    return SignalFilter<T>.where(
      (payload, _) => _payloadScheduleId(payload as Object) == entryId,
    );
  }

  static String? _payloadScheduleId(Object payload) {
    if (payload is ScheduleEntryDuePayload) return payload.entry.id;
    if (payload is ScheduleEntryDispatchedPayload) return payload.entry.id;
    if (payload is ScheduleEntryFailedPayload) return payload.entry.id;
    return null;
  }

  static SignalFilter<T>? _commandTypeFilter<T>(String? commandType) {
    if (commandType == null) return null;
    return SignalFilter<T>.where(
      (payload, _) => _payloadCommandType(payload as Object) == commandType,
    );
  }

  static String? _payloadCommandType(Object payload) {
    if (payload is ControlCommandReceivedPayload) {
      return payload.command.type;
    }
    if (payload is ControlCommandCompletedPayload) {
      return payload.command.type;
    }
    return null;
  }

  static SignalDispatchConfig _dispatchConfigFor(String name) =>
      SignalDispatchConfig(
        enabled: _configuration.isEnabled(name),
        onError: _handleDispatchError,
      );

  static void _handleDispatchError(
    String signalName,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_errorReporter != null) {
      _errorReporter!(signalName, error, stackTrace);
      return;
    }
    stemLogger.warning(
      'Signal {signal} handler failed: {error}',
      Context({
        'signal': signalName,
        'error': error.toString(),
        'stack': stackTrace.toString(),
      }),
    );
  }
}
