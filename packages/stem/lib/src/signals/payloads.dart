import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/core/stem_event.dart';

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
class BeforeTaskPublishPayload implements StemEvent {
  /// Creates a new [BeforeTaskPublishPayload] instance.
  const BeforeTaskPublishPayload({
    required this.envelope,
    required this.attempt,
  });

  /// The task envelope to be published.
  final Envelope envelope;

  /// The attempt number for this task.
  final int attempt;

  @override
  String get eventName => 'before-task-publish';

  @override
  DateTime get occurredAt => envelope.enqueuedAt.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'taskId': envelope.id,
    'taskName': envelope.name,
    'queue': envelope.queue,
    'attempt': attempt,
  };
}

/// Payload emitted after a task has been published to the broker.
class AfterTaskPublishPayload implements StemEvent {
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

  @override
  String get eventName => 'after-task-publish';

  @override
  DateTime get occurredAt => envelope.enqueuedAt.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': envelope.name,
    'queue': envelope.queue,
    'attempt': attempt,
  };
}

/// Payload emitted when a task is received by a worker.
class TaskReceivedPayload implements StemEvent {
  /// Creates a new [TaskReceivedPayload] instance.
  TaskReceivedPayload({
    required this.envelope,
    required this.worker,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope that was received.
  final Envelope envelope;

  /// The worker that received the task.
  final WorkerInfo worker;

  final DateTime _occurredAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  @override
  String get eventName => 'task-received';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'workerId': worker.id,
  };
}

/// Payload emitted before a task begins execution.
class TaskPrerunPayload implements StemEvent {
  /// Creates a new [TaskPrerunPayload] instance.
  TaskPrerunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope to be executed.
  final Envelope envelope;

  /// The worker that will execute the task.
  final WorkerInfo worker;

  /// The execution context for the task.
  final TaskContext context;

  final DateTime _occurredAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;

  @override
  String get eventName => 'task-prerun';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'attempt': attempt,
    'workerId': worker.id,
  };
}

/// Payload emitted after a task finishes execution.
class TaskPostrunPayload implements StemEvent {
  /// Creates a new [TaskPostrunPayload] instance.
  TaskPostrunPayload({
    required this.envelope,
    required this.worker,
    required this.context,
    required this.result,
    required this.state,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope that was executed.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The execution context for the task.
  final TaskContext context;

  /// The result returned by the task.
  final Object? result;

  /// Decodes the task result with [codec].
  TResult? resultAs<TResult>({required PayloadCodec<TResult> codec}) {
    final stored = result;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the task result with a JSON decoder.
  TResult? resultJson<TResult>({
    required TResult Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = result;
    if (stored == null) return null;
    return PayloadCodec<TResult>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// The final state of the task.
  final TaskState state;

  final DateTime _occurredAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;

  @override
  String get eventName => 'task-postrun';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'attempt': attempt,
    'workerId': worker.id,
    'state': state.name,
  };
}

/// Payload emitted when a task is scheduled for retry.
class TaskRetryPayload implements StemEvent {
  /// Creates a new [TaskRetryPayload] instance.
  TaskRetryPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
    required this.nextRetryAt,
    DateTime? emittedAt,
  }) : emittedAt = (emittedAt ?? stemNow()).toUtc();

  /// The task envelope to be retried.
  final Envelope envelope;

  /// The worker that will retry the task.
  final WorkerInfo worker;

  /// The reason for the retry.
  final Object reason;

  /// The scheduled time for the next retry attempt.
  final DateTime nextRetryAt;

  /// The timestamp when the retry signal was emitted.
  final DateTime emittedAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;

  @override
  String get eventName => 'task-retry';

  @override
  DateTime get occurredAt => emittedAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'attempt': attempt,
    'workerId': worker.id,
    'reason': reason.toString(),
    'emittedAt': emittedAt.toIso8601String(),
    'nextRetryAt': nextRetryAt.toUtc().toIso8601String(),
  };
}

/// Payload emitted when a task completes successfully.
class TaskSuccessPayload implements StemEvent {
  /// Creates a new [TaskSuccessPayload] instance.
  TaskSuccessPayload({
    required this.envelope,
    required this.worker,
    required this.result,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope that completed successfully.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The result returned by the successful task.
  final Object? result;

  /// Decodes the task result with [codec].
  TResult? resultAs<TResult>({required PayloadCodec<TResult> codec}) {
    final stored = result;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the task result with a JSON decoder.
  TResult? resultJson<TResult>({
    required TResult Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = result;
    if (stored == null) return null;
    return PayloadCodec<TResult>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  final DateTime _occurredAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;

  @override
  String get eventName => 'task-succeeded';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'attempt': attempt,
    'workerId': worker.id,
  };
}

/// Payload emitted when a task fails.
class TaskFailurePayload implements StemEvent {
  /// Creates a new [TaskFailurePayload] instance.
  TaskFailurePayload({
    required this.envelope,
    required this.worker,
    required this.error,
    required this.stackTrace,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope that failed.
  final Envelope envelope;

  /// The worker that executed the task.
  final WorkerInfo worker;

  /// The error that caused the task to fail.
  final Object error;

  /// The stack trace associated with the failure, if available.
  final StackTrace? stackTrace;

  final DateTime _occurredAt;

  /// The unique identifier for the task.
  String get taskId => envelope.id;

  /// The name of the task.
  String get taskName => envelope.name;

  /// The attempt number for this task execution.
  int get attempt => envelope.attempt;

  @override
  String get eventName => 'task-failed';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': taskId,
    'taskName': taskName,
    'queue': envelope.queue,
    'attempt': attempt,
    'workerId': worker.id,
    'error': error.toString(),
    if (stackTrace != null) 'stackTrace': stackTrace.toString(),
  };
}

/// Payload emitted when a task is revoked.
class TaskRevokedPayload implements StemEvent {
  /// Creates a new [TaskRevokedPayload] instance.
  TaskRevokedPayload({
    required this.envelope,
    required this.worker,
    required this.reason,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The task envelope that was revoked.
  final Envelope envelope;

  /// The worker that was executing the task.
  final WorkerInfo worker;

  /// The reason for revoking the task.
  final String reason;

  final DateTime _occurredAt;

  @override
  String get eventName => 'task-revoked';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'taskId': envelope.id,
    'taskName': envelope.name,
    'queue': envelope.queue,
    'workerId': worker.id,
    'reason': reason,
  };
}

/// Payload emitted for worker lifecycle events (start, stop, etc.).
class WorkerLifecyclePayload implements StemEvent {
  /// Creates a new [WorkerLifecyclePayload] instance.
  WorkerLifecyclePayload({
    required this.worker,
    this.reason,
    this.signalName = 'worker-lifecycle',
    DateTime? timestamp,
  }) : _occurredAt = (timestamp ?? stemNow()).toUtc();

  /// The worker involved in the lifecycle event.
  final WorkerInfo worker;

  /// Optional reason for the lifecycle event (e.g., shutdown reason).
  final String? reason;

  /// Canonical signal name for this lifecycle event.
  final String signalName;

  final DateTime _occurredAt;

  @override
  String get eventName => signalName;

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'workerId': worker.id,
    'queues': worker.queues,
    'broadcasts': worker.broadcasts,
    if (reason != null) 'reason': reason,
  };
}

/// Payload emitted when a worker sends a heartbeat.
class WorkerHeartbeatPayload implements StemEvent {
  /// Creates a new [WorkerHeartbeatPayload] instance.
  const WorkerHeartbeatPayload({required this.worker, required this.timestamp});

  /// The worker sending the heartbeat.
  final WorkerInfo worker;

  /// The timestamp when the heartbeat was sent.
  final DateTime timestamp;

  @override
  String get eventName => 'worker-heartbeat';

  @override
  DateTime get occurredAt => timestamp.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'workerId': worker.id,
    'queues': worker.queues,
    'broadcasts': worker.broadcasts,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}

/// Payload emitted for worker child isolate lifecycle events.
class WorkerChildLifecyclePayload implements StemEvent {
  /// Creates a new [WorkerChildLifecyclePayload] instance.
  WorkerChildLifecyclePayload({
    required this.worker,
    required this.isolateId,
    this.signalName = 'worker-child-lifecycle',
    DateTime? timestamp,
  }) : _occurredAt = (timestamp ?? stemNow()).toUtc();

  /// The parent worker managing the child isolate.
  final WorkerInfo worker;

  /// The unique identifier for the child isolate.
  final int isolateId;

  /// Canonical signal name for this child lifecycle event.
  final String signalName;

  final DateTime _occurredAt;

  @override
  String get eventName => signalName;

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'workerId': worker.id,
    'isolateId': isolateId,
  };
}

/// Payload emitted for workflow run events.
class WorkflowRunPayload implements StemEvent {
  /// Creates a new [WorkflowRunPayload] instance.
  WorkflowRunPayload({
    required this.runId,
    required this.workflow,
    required this.status,
    this.step,
    this.metadata = const {},
    this.signalName,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

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

  /// Returns the decoded metadata value for [key], or `null` when absent.
  ///
  /// When [codec] is supplied, the stored durable payload is decoded through
  /// that codec before being returned.
  T? metadataValue<T>(String key, {PayloadCodec<T>? codec}) {
    return metadata.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with [codec].
  T? metadataAs<T>(String key, {required PayloadCodec<T> codec}) {
    return metadata.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with a JSON decoder.
  T? metadataJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return metadata.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded metadata value for [key], or [fallback] when absent.
  T metadataValueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return metadata.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded metadata value for [key], throwing when absent.
  T requiredMetadataValue<T>(String key, {PayloadCodec<T>? codec}) {
    return metadata.requiredValue<T>(key, codec: codec);
  }

  /// Optional canonical signal name when this payload is emitted.
  final String? signalName;

  final DateTime _occurredAt;

  @override
  String get eventName => signalName ?? 'workflow-run-${status.name}';

  @override
  DateTime get occurredAt => _occurredAt;

  /// Returns a copy of this payload bound to a concrete signal name.
  WorkflowRunPayload withSignalName(String signalName) => WorkflowRunPayload(
    runId: runId,
    workflow: workflow,
    status: status,
    step: step,
    metadata: metadata,
    signalName: signalName,
    occurredAt: _occurredAt,
  );

  @override
  Map<String, Object?> get attributes => {
    'runId': runId,
    'workflow': workflow,
    'status': status.name,
    if (step != null) 'step': step,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// Payload emitted when a schedule entry becomes due for execution.
class ScheduleEntryDuePayload implements StemEvent {
  /// Creates a new [ScheduleEntryDuePayload] instance.
  const ScheduleEntryDuePayload({required this.entry, required this.tickAt});

  /// The schedule entry that is due.
  final ScheduleEntry entry;

  /// The time at which the entry became due.
  final DateTime tickAt;

  @override
  String get eventName => 'schedule-entry-due';

  @override
  DateTime get occurredAt => tickAt.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'entryId': entry.id,
    'tickAt': tickAt.toUtc().toIso8601String(),
  };
}

/// Payload emitted when a schedule entry has been dispatched.
class ScheduleEntryDispatchedPayload implements StemEvent {
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

  @override
  String get eventName => 'schedule-entry-dispatched';

  @override
  DateTime get occurredAt => executedAt.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'entryId': entry.id,
    'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    'executedAt': executedAt.toUtc().toIso8601String(),
    'driftMs': drift.inMilliseconds,
  };
}

/// Payload emitted when a schedule entry fails to execute.
class ScheduleEntryFailedPayload implements StemEvent {
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

  @override
  String get eventName => 'schedule-entry-failed';

  @override
  DateTime get occurredAt => scheduledFor.toUtc();

  @override
  Map<String, Object?> get attributes => {
    'entryId': entry.id,
    'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    'error': error.toString(),
    'stackTrace': stackTrace.toString(),
  };
}

/// Payload emitted when a control command is received by a worker.
class ControlCommandReceivedPayload implements StemEvent {
  /// Creates a new [ControlCommandReceivedPayload] instance.
  ControlCommandReceivedPayload({
    required this.worker,
    required this.command,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

  /// The worker that received the command.
  final WorkerInfo worker;

  /// The control command that was received.
  final ControlCommandMessage command;

  final DateTime _occurredAt;

  @override
  String get eventName => 'control-command-received';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'workerId': worker.id,
    'requestId': command.requestId,
    'type': command.type,
    'targets': command.targets,
    'payload': command.payload,
    if (command.timeoutMs != null) 'timeoutMs': command.timeoutMs,
  };
}

/// Payload emitted when a control command completes execution.
class ControlCommandCompletedPayload implements StemEvent {
  /// Creates a new [ControlCommandCompletedPayload] instance.
  ControlCommandCompletedPayload({
    required this.worker,
    required this.command,
    required this.status,
    this.response,
    this.error,
    DateTime? occurredAt,
  }) : _occurredAt = (occurredAt ?? stemNow()).toUtc();

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

  final DateTime _occurredAt;

  @override
  String get eventName => 'control-command-completed';

  @override
  DateTime get occurredAt => _occurredAt;

  @override
  Map<String, Object?> get attributes => {
    'workerId': worker.id,
    'requestId': command.requestId,
    'type': command.type,
    'status': status,
    if (response != null) 'response': response,
    if (error != null) 'error': error,
  };
}
