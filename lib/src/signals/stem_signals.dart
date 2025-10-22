import 'package:contextual/contextual.dart';

import '../observability/logging.dart';
import 'payloads.dart';
import 'signal.dart';

typedef SignalErrorReporter = void Function(
  String signalName,
  Object error,
  StackTrace stackTrace,
);

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
    return afterTaskPublish.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskPrerun(
    SignalHandler<TaskPrerunPayload> handler, {
    String? taskName,
  }) {
    return taskPrerun.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskPostrun(
    SignalHandler<TaskPostrunPayload> handler, {
    String? taskName,
  }) {
    return taskPostrun.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskSuccess(
    SignalHandler<TaskSuccessPayload> handler, {
    String? taskName,
  }) {
    return taskSucceeded.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskFailure(
    SignalHandler<TaskFailurePayload> handler, {
    String? taskName,
  }) {
    return taskFailed.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskRetry(
    SignalHandler<TaskRetryPayload> handler, {
    String? taskName,
  }) {
    return taskRetry.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskReceived(
    SignalHandler<TaskReceivedPayload> handler, {
    String? taskName,
  }) {
    return taskReceived.connect(
      handler,
      filter: _taskNameFilter(taskName),
    );
  }

  static SignalSubscription onTaskRevoked(
    SignalHandler<TaskRevokedPayload> handler, {
    String? taskName,
  }) {
    return taskRevoked.connect(
      handler,
      filter: _taskNameFilter(taskName),
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
