import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';

/// Status of a workflow run emitted via signals.
enum WorkflowRunStatus {
  /// The workflow is currently running.
  running,

  /// The workflow has been suspended.
  suspended,

  /// The workflow has completed successfully.
  completed,

  /// The workflow has failed.
  failed,

  /// The workflow was cancelled.
  cancelled,
}

/// Basic metadata representing a worker that emitted a signal.
class WorkerInfo {
  /// Creates a new [WorkerInfo] instance.
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

/// Payload emitted before a task is published to the broker.
class BeforeTaskPublishPayload {
  /// Creates a new [BeforeTaskPublishPayload] instance.
  const BeforeTaskPublishPayload({
    required this.envelope,
    required this.attempt,
  });

  /// The task envelope to be published.
  final Envelope envelope;

  /// The attempt number for this task.
  final int attempt;
}

/// Payload emitted after a task has been published to the broker.
class AfterTaskPublishPayload {
  /// Creates a new [AfterTaskPublishPayload] instance.
  const AfterTaskPublishPayload({
    required this.envelope,
    required this.attempt,
    required this.taskId,
  });

  /// The task envelope that was published.
  final Envelope envelope;

  /// The attempt number for this task.
  final int attempt;

  /// The unique identifier for the task.
  final String taskId;
}

/// Payload emitted when a task is received by a worker.
class TaskReceivedPayload {
  /// Creates a new [TaskReceivedPayload] instance.
  const TaskReceivedPayload({required this.envelope, required this.worker});

  /// The task envelope that was received.
  final Envelope envelope;

  /// The worker that received the task.
  final WorkerInfo worker;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;
}

/// Payload emitted before a task begins execution.
class TaskPrerunPayload {
  /// Creates a new [TaskPrerunPayload] instance.
  const TaskPrerunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
  });

  /// The task envelope to be executed.
  final Envelope envelope;

  /// The worker that will execute the task.
  final WorkerInfo worker;

  /// The execution context for the task.
  final TaskContext context;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;
}

/// Payload emitted after a task finishes execution.
class TaskPostrunPayload {
  /// Creates a new [TaskPostrunPayload] instance.
  const TaskPostrunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
    required this.result,
    required this.state,
  });

  /// The task envelope that was executed.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The execution context for the task.
  final TaskContext context;

  /// The result returned by the task.
  final Object? result;

  /// The final state of the task.
  final TaskState state;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;
}

/// Payload emitted when a task is scheduled for retry.
class TaskRetryPayload {
  /// Creates a new [TaskRetryPayload] instance.
  const TaskRetryPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
    required this.nextRetryAt,
  });

  /// The task envelope to be retried.
  final Envelope envelope;

  /// The worker that will retry the task.
  final WorkerInfo worker;

  /// The reason for the retry.
  final Object reason;

  /// The scheduled time for the next retry attempt.
  final DateTime nextRetryAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;
}

/// Payload emitted when a task completes successfully.
class TaskSuccessPayload {
  /// Creates a new [TaskSuccessPayload] instance.
  const TaskSuccessPayload({
    required this.envelope,
    required this.worker,
    required this.result,
  });

  /// The task envelope that completed successfully.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The result returned by the successful task.
  final Object? result;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;
}

/// Payload emitted when a task fails.
class TaskFailurePayload {
  /// Creates a new [TaskFailurePayload] instance.
  const TaskFailurePayload({
    required this.envelope,
    required this.worker,
    required this.error,
    required this.stackTrace,
  });

  /// The task envelope that failed.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The error that caused the task to fail.
  final Object error;

  /// The stack trace associated with the failure, if available.
  final StackTrace? stackTrace;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;
}

/// Payload emitted when a task is revoked.
class TaskRevokedPayload {
  /// Creates a new [TaskRevokedPayload] instance.
  const TaskRevokedPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
  });

  /// The task envelope that was revoked.
  final Envelope envelope;

  /// The worker that was executing the task.
  final WorkerInfo worker;

  /// The reason for revoking the task.
  final String reason;
}

/// Payload emitted for worker lifecycle events (start, stop, etc.).
class WorkerLifecyclePayload {
  /// Creates a new [WorkerLifecyclePayload] instance.
  const WorkerLifecyclePayload({required this.worker, this.reason});

  /// The worker involved in the lifecycle event.
  final WorkerInfo worker;

  /// Optional reason for the lifecycle event (e.g., shutdown reason).
  final String? reason;
}

/// Payload emitted when a worker sends a heartbeat.
class WorkerHeartbeatPayload {
  /// Creates a new [WorkerHeartbeatPayload] instance.
  const WorkerHeartbeatPayload({required this.worker, required this.timestamp});

  /// The worker sending the heartbeat.
  final WorkerInfo worker;

  /// The timestamp when the heartbeat was sent.
  final DateTime timestamp;
}

/// Payload emitted for worker child isolate lifecycle events.
class WorkerChildLifecyclePayload {
  /// Creates a new [WorkerChildLifecyclePayload] instance.
  const WorkerChildLifecyclePayload({
    required this.worker,
    required this.isolateId,
  });

  /// The parent worker managing the child isolate.
  final WorkerInfo worker;

  /// The unique identifier for the child isolate.
  final int isolateId;
}

/// Payload emitted for workflow run events.
class WorkflowRunPayload {
  /// Creates a new [WorkflowRunPayload] instance.
  const WorkflowRunPayload({
    required this.runId,
    required this.workflow,
    required this.status,
    this.step,
    this.metadata = const {},
  });

  /// The unique identifier for the workflow run.
  final String runId;

  /// The name of the workflow.
  final String workflow;

  /// The current status of the workflow run.
  final WorkflowRunStatus status;

  /// The current step being executed, if applicable.
  final String? step;

  /// Additional metadata associated with the workflow run.
  final Map<String, Object?> metadata;
}

/// Payload emitted when a schedule entry becomes due for execution.
class ScheduleEntryDuePayload {
  /// Creates a new [ScheduleEntryDuePayload] instance.
  const ScheduleEntryDuePayload({required this.entry, required this.tickAt});

  /// The schedule entry that is due.
  final ScheduleEntry entry;

  /// The time at which the entry became due.
  final DateTime tickAt;
}

/// Payload emitted when a schedule entry has been dispatched.
class ScheduleEntryDispatchedPayload {
  /// Creates a new [ScheduleEntryDispatchedPayload] instance.
  const ScheduleEntryDispatchedPayload({
    required this.entry,
    required this.scheduledFor,
    required this.executedAt,
    required this.drift,
  });

  /// The schedule entry that was dispatched.
  final ScheduleEntry entry;

  /// The time for which the entry was scheduled.
  final DateTime scheduledFor;

  /// The actual time when the entry was executed.
  final DateTime executedAt;

  /// The time difference between scheduled and actual execution.
  final Duration drift;
}

/// Payload emitted when a schedule entry fails to execute.
class ScheduleEntryFailedPayload {
  /// Creates a new [ScheduleEntryFailedPayload] instance.
  const ScheduleEntryFailedPayload({
    required this.entry,
    required this.scheduledFor,
    required this.error,
    required this.stackTrace,
  });

  /// The schedule entry that failed.
  final ScheduleEntry entry;

  /// The time for which the entry was scheduled.
  final DateTime scheduledFor;

  /// The error that caused the failure.
  final Object error;

  /// The stack trace associated with the error.
  final StackTrace stackTrace;
}

/// Payload emitted when a control command is received by a worker.
class ControlCommandReceivedPayload {
  /// Creates a new [ControlCommandReceivedPayload] instance.
  const ControlCommandReceivedPayload({
    required this.worker,
    required this.command,
  });

  /// The worker that received the command.
  final WorkerInfo worker;

  /// The control command that was received.
  final ControlCommandMessage command;
}

/// Payload emitted when a control command completes execution.
class ControlCommandCompletedPayload {
  /// Creates a new [ControlCommandCompletedPayload] instance.
  const ControlCommandCompletedPayload({
    required this.worker,
    required this.command,
    required this.status,
    this.response,
    this.error,
  });

  /// The worker that executed the command.
  final WorkerInfo worker;

  /// The control command that was executed.
  final ControlCommandMessage command;

  /// The status of the command execution (e.g., 'success', 'error').
  final String status;

  /// The response data from the command execution, if any.
  final Map<String, Object?>? response;

  /// Error information if the command failed, if any.
  final Map<String, Object?>? error;
}
