import 'package:contextual/contextual.dart';

import '../observability/logging.dart';
import 'payloads.dart';
import 'signal.dart';

typedef SignalErrorReporter =
    void Function(String signalName, Object error, StackTrace stackTrace);

class StemSignalConfiguration {
  const StemSignalConfiguration({
    this.enabled = true,
    Map<String, bool>? enabledSignals,
  }) : enabledSignals = enabledSignals ?? const {};

  final bool enabled;
  final Map<String, bool> enabledSignals;

  bool isEnabled(String name) => enabled && (enabledSignals[name] ?? true);

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

class StemSignals {
  static const String beforeTaskPublishName = 'before-task-publish';
  static const String afterTaskPublishName = 'after-task-publish';
  static const String taskReceivedName = 'task-received';
  static const String taskPrerunName = 'task-prerun';
  static const String taskPostrunName = 'task-postrun';
  static const String taskRetryName = 'task-retry';
  static const String taskSucceededName = 'task-succeeded';
  static const String taskFailedName = 'task-failed';
  static const String taskRevokedName = 'task-revoked';
  static const String workerInitName = 'worker-init';
  static const String workerReadyName = 'worker-ready';
  static const String workerStoppingName = 'worker-stopping';
  static const String workerShutdownName = 'worker-shutdown';
  static const String workerHeartbeatName = 'worker-heartbeat';
  static const String workerChildInitName = 'worker-child-init';
  static const String workerChildShutdownName = 'worker-child-shutdown';
  static const String scheduleEntryDueName = 'schedule-entry-due';
  static const String scheduleEntryDispatchedName = 'schedule-entry-dispatched';
  static const String scheduleEntryFailedName = 'schedule-entry-failed';
  static const String controlCommandReceivedName = 'control-command-received';
  static const String controlCommandCompletedName = 'control-command-completed';
  static const String workflowRunStartedName = 'workflow-run-started';
  static const String workflowRunSuspendedName = 'workflow-run-suspended';
  static const String workflowRunResumedName = 'workflow-run-resumed';
  static const String workflowRunCompletedName = 'workflow-run-completed';
  static const String workflowRunFailedName = 'workflow-run-failed';
  static const String workflowRunCancelledName = 'workflow-run-cancelled';

  static StemSignalConfiguration _configuration =
      const StemSignalConfiguration();
  static SignalErrorReporter? _errorReporter;

  static final Signal<BeforeTaskPublishPayload> beforeTaskPublish =
      Signal<BeforeTaskPublishPayload>(
        name: beforeTaskPublishName,
        config: _dispatchConfigFor(beforeTaskPublishName),
      );

  static final Signal<AfterTaskPublishPayload> afterTaskPublish =
      Signal<AfterTaskPublishPayload>(
        name: afterTaskPublishName,
        config: _dispatchConfigFor(afterTaskPublishName),
      );

  static final Signal<TaskReceivedPayload> taskReceived =
      Signal<TaskReceivedPayload>(
        name: taskReceivedName,
        config: _dispatchConfigFor(taskReceivedName),
      );

  static final Signal<TaskPrerunPayload> taskPrerun = Signal<TaskPrerunPayload>(
    name: taskPrerunName,
    config: _dispatchConfigFor(taskPrerunName),
  );

  static final Signal<TaskPostrunPayload> taskPostrun =
      Signal<TaskPostrunPayload>(
        name: taskPostrunName,
        config: _dispatchConfigFor(taskPostrunName),
      );

  static final Signal<TaskRetryPayload> taskRetry = Signal<TaskRetryPayload>(
    name: taskRetryName,
    config: _dispatchConfigFor(taskRetryName),
  );

  static final Signal<TaskSuccessPayload> taskSucceeded =
      Signal<TaskSuccessPayload>(
        name: taskSucceededName,
        config: _dispatchConfigFor(taskSucceededName),
      );

  static final Signal<TaskFailurePayload> taskFailed =
      Signal<TaskFailurePayload>(
        name: taskFailedName,
        config: _dispatchConfigFor(taskFailedName),
      );

  static final Signal<TaskRevokedPayload> taskRevoked =
      Signal<TaskRevokedPayload>(
        name: taskRevokedName,
        config: _dispatchConfigFor(taskRevokedName),
      );

  static final Signal<WorkerLifecyclePayload> workerInit =
      Signal<WorkerLifecyclePayload>(
        name: workerInitName,
        config: _dispatchConfigFor(workerInitName),
      );

  static final Signal<WorkerLifecyclePayload> workerReady =
      Signal<WorkerLifecyclePayload>(
        name: workerReadyName,
        config: _dispatchConfigFor(workerReadyName),
      );

  static final Signal<WorkerLifecyclePayload> workerStopping =
      Signal<WorkerLifecyclePayload>(
        name: workerStoppingName,
        config: _dispatchConfigFor(workerStoppingName),
      );

  static final Signal<WorkerLifecyclePayload> workerShutdown =
      Signal<WorkerLifecyclePayload>(
        name: workerShutdownName,
        config: _dispatchConfigFor(workerShutdownName),
      );

  static final Signal<WorkerHeartbeatPayload> workerHeartbeat =
      Signal<WorkerHeartbeatPayload>(
        name: workerHeartbeatName,
        config: _dispatchConfigFor(workerHeartbeatName),
      );

  static final Signal<WorkerChildLifecyclePayload> workerChildInit =
      Signal<WorkerChildLifecyclePayload>(
        name: workerChildInitName,
        config: _dispatchConfigFor(workerChildInitName),
      );

  static final Signal<WorkerChildLifecyclePayload> workerChildShutdown =
      Signal<WorkerChildLifecyclePayload>(
        name: workerChildShutdownName,
        config: _dispatchConfigFor(workerChildShutdownName),
      );

  static final Signal<WorkflowRunPayload> workflowRunStarted =
      Signal<WorkflowRunPayload>(
        name: workflowRunStartedName,
        config: _dispatchConfigFor(workflowRunStartedName),
      );

  static final Signal<WorkflowRunPayload> workflowRunSuspended =
      Signal<WorkflowRunPayload>(
        name: workflowRunSuspendedName,
        config: _dispatchConfigFor(workflowRunSuspendedName),
      );

  static final Signal<WorkflowRunPayload> workflowRunResumed =
      Signal<WorkflowRunPayload>(
        name: workflowRunResumedName,
        config: _dispatchConfigFor(workflowRunResumedName),
      );

  static final Signal<WorkflowRunPayload> workflowRunCompleted =
      Signal<WorkflowRunPayload>(
        name: workflowRunCompletedName,
        config: _dispatchConfigFor(workflowRunCompletedName),
      );

  static final Signal<WorkflowRunPayload> workflowRunFailed =
      Signal<WorkflowRunPayload>(
        name: workflowRunFailedName,
        config: _dispatchConfigFor(workflowRunFailedName),
      );

  static final Signal<WorkflowRunPayload> workflowRunCancelled =
      Signal<WorkflowRunPayload>(
        name: workflowRunCancelledName,
        config: _dispatchConfigFor(workflowRunCancelledName),
      );

  static final Signal<ScheduleEntryDuePayload> scheduleEntryDue =
      Signal<ScheduleEntryDuePayload>(
        name: scheduleEntryDueName,
        config: _dispatchConfigFor(scheduleEntryDueName),
      );

  static final Signal<ScheduleEntryDispatchedPayload> scheduleEntryDispatched =
      Signal<ScheduleEntryDispatchedPayload>(
        name: scheduleEntryDispatchedName,
        config: _dispatchConfigFor(scheduleEntryDispatchedName),
      );

  static final Signal<ScheduleEntryFailedPayload> scheduleEntryFailed =
      Signal<ScheduleEntryFailedPayload>(
        name: scheduleEntryFailedName,
        config: _dispatchConfigFor(scheduleEntryFailedName),
      );

  static final Signal<ControlCommandReceivedPayload> controlCommandReceived =
      Signal<ControlCommandReceivedPayload>(
        name: controlCommandReceivedName,
        config: _dispatchConfigFor(controlCommandReceivedName),
      );

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

  static void _applyConfiguration() {
    for (final signal in _allSignals) {
      signal.config = _dispatchConfigFor(signal.name);
    }
  }

  static SignalSubscription onBeforeTaskPublish(
    SignalHandler<BeforeTaskPublishPayload> handler, {
    String? taskName,
  }) {
    return beforeTaskPublish.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onAfterTaskPublish(
    SignalHandler<AfterTaskPublishPayload> handler, {
    String? taskName,
  }) {
    return afterTaskPublish.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskPrerun(
    SignalHandler<TaskPrerunPayload> handler, {
    String? taskName,
  }) {
    return taskPrerun.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskPostrun(
    SignalHandler<TaskPostrunPayload> handler, {
    String? taskName,
  }) {
    return taskPostrun.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskSuccess(
    SignalHandler<TaskSuccessPayload> handler, {
    String? taskName,
  }) {
    return taskSucceeded.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskFailure(
    SignalHandler<TaskFailurePayload> handler, {
    String? taskName,
  }) {
    return taskFailed.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskRetry(
    SignalHandler<TaskRetryPayload> handler, {
    String? taskName,
  }) {
    return taskRetry.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskReceived(
    SignalHandler<TaskReceivedPayload> handler, {
    String? taskName,
  }) {
    return taskReceived.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onTaskRevoked(
    SignalHandler<TaskRevokedPayload> handler, {
    String? taskName,
  }) {
    return taskRevoked.connect(handler, filter: _taskNameFilter(taskName));
  }

  static SignalSubscription onWorkerHeartbeat(
    SignalHandler<WorkerHeartbeatPayload> handler, {
    String? workerId,
  }) {
    return workerHeartbeat.connect(handler, filter: _workerIdFilter(workerId));
  }

  static SignalSubscription onWorkerChildInit(
    SignalHandler<WorkerChildLifecyclePayload> handler, {
    String? workerId,
  }) {
    return workerChildInit.connect(handler, filter: _workerIdFilter(workerId));
  }

  static SignalSubscription onWorkerChildShutdown(
    SignalHandler<WorkerChildLifecyclePayload> handler, {
    String? workerId,
  }) {
    return workerChildShutdown.connect(
      handler,
      filter: _workerIdFilter(workerId),
    );
  }

  static SignalSubscription onScheduleEntryDue(
    SignalHandler<ScheduleEntryDuePayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryDue.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  static SignalSubscription onScheduleEntryDispatched(
    SignalHandler<ScheduleEntryDispatchedPayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryDispatched.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  static SignalSubscription onScheduleEntryFailed(
    SignalHandler<ScheduleEntryFailedPayload> handler, {
    String? entryId,
  }) {
    return scheduleEntryFailed.connect(
      handler,
      filter: _scheduleIdFilter(entryId),
    );
  }

  static SignalSubscription onControlCommandReceived(
    SignalHandler<ControlCommandReceivedPayload> handler, {
    String? commandType,
  }) {
    return controlCommandReceived.connect(
      handler,
      filter: _commandTypeFilter(commandType),
    );
  }

  static SignalSubscription onControlCommandCompleted(
    SignalHandler<ControlCommandCompletedPayload> handler, {
    String? commandType,
  }) {
    return controlCommandCompleted.connect(
      handler,
      filter: _commandTypeFilter(commandType),
    );
  }

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
