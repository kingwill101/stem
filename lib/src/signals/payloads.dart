import '../control/control_messages.dart';
import '../core/contracts.dart';
import '../core/envelope.dart';

/// Basic metadata representing a worker that emitted a signal.
class WorkerInfo {
  const WorkerInfo({
    required this.id,
    required this.queues,
    required this.broadcasts,
  });

  /// Consumer identifier or generated ID.
  final String id;

  /// Queues the worker is subscribed to.
  final List<String> queues;

  /// Broadcast channels the worker is subscribed to.
  final List<String> broadcasts;
}

class BeforeTaskPublishPayload {
  const BeforeTaskPublishPayload({
    required this.envelope,
    required this.attempt,
  });

  final Envelope envelope;
  final int attempt;
}

class AfterTaskPublishPayload {
  const AfterTaskPublishPayload({
    required this.envelope,
    required this.attempt,
    required this.taskId,
  });

  final Envelope envelope;
  final int attempt;
  final String taskId;
}

class TaskReceivedPayload {
  const TaskReceivedPayload({
    required this.envelope,
    required this.worker,
  });

  final Envelope envelope;
  final WorkerInfo worker;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
}

class TaskPrerunPayload {
  const TaskPrerunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final TaskContext context;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
  int get attempt => envelope.attempt;
}

class TaskPostrunPayload {
  const TaskPostrunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
    required this.result,
    required this.state,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final TaskContext context;
  final Object? result;
  final TaskState state;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
  int get attempt => envelope.attempt;
}

class TaskRetryPayload {
  const TaskRetryPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
    required this.nextRetryAt,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final Object reason;
  final DateTime nextRetryAt;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
  int get attempt => envelope.attempt;
}

class TaskSuccessPayload {
  const TaskSuccessPayload({
    required this.envelope,
    required this.worker,
    required this.result,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final Object? result;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
  int get attempt => envelope.attempt;
}

class TaskFailurePayload {
  const TaskFailurePayload({
    required this.envelope,
    required this.worker,
    required this.error,
    required this.stackTrace,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final Object error;
  final StackTrace? stackTrace;

  String get taskId => envelope.id;
  String get taskName => envelope.name;
  int get attempt => envelope.attempt;
}

class TaskRevokedPayload {
  const TaskRevokedPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
  });

  final Envelope envelope;
  final WorkerInfo worker;
  final String reason;
}

class WorkerLifecyclePayload {
  const WorkerLifecyclePayload({
    required this.worker,
    this.reason,
  });

  final WorkerInfo worker;
  final String? reason;
}

class WorkerHeartbeatPayload {
  const WorkerHeartbeatPayload({
    required this.worker,
    required this.timestamp,
  });

  final WorkerInfo worker;
  final DateTime timestamp;
}

class WorkerChildLifecyclePayload {
  const WorkerChildLifecyclePayload({
    required this.worker,
    required this.isolateId,
  });

  final WorkerInfo worker;
  final int isolateId;
}

class ScheduleEntryDuePayload {
  const ScheduleEntryDuePayload({
    required this.entry,
    required this.tickAt,
  });

  final ScheduleEntry entry;
  final DateTime tickAt;
}

class ScheduleEntryDispatchedPayload {
  const ScheduleEntryDispatchedPayload({
    required this.entry,
    required this.scheduledFor,
    required this.executedAt,
    required this.drift,
  });

  final ScheduleEntry entry;
  final DateTime scheduledFor;
  final DateTime executedAt;
  final Duration drift;
}

class ScheduleEntryFailedPayload {
  const ScheduleEntryFailedPayload({
    required this.entry,
    required this.scheduledFor,
    required this.error,
    required this.stackTrace,
  });

  final ScheduleEntry entry;
  final DateTime scheduledFor;
  final Object error;
  final StackTrace stackTrace;
}

class ControlCommandReceivedPayload {
  const ControlCommandReceivedPayload({
    required this.worker,
    required this.command,
  });

  final WorkerInfo worker;
  final ControlCommandMessage command;
}

class ControlCommandCompletedPayload {
  const ControlCommandCompletedPayload({
    required this.worker,
    required this.command,
    required this.status,
    this.response,
    this.error,
  });

  final WorkerInfo worker;
  final ControlCommandMessage command;
  final String status;
  final Map<String, Object?>? response;
  final Map<String, Object?>? error;
}
