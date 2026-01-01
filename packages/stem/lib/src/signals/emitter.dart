import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:stem/src/signals/stem_signals.dart';

/// Helper used by coordinators, workers, and middleware to emit strongly
/// typed Stem signals without duplicating payload construction.
class StemSignalEmitter {
  /// Creates a signal emitter with an optional default sender.
  const StemSignalEmitter({this.defaultSender});

  /// Optional sender identifier applied when no explicit sender is supplied.
  final String? defaultSender;

  String? _senderOverride(String? sender) => sender ?? defaultSender;

  /// Emits the before-task-publish signal.
  Future<void> beforeTaskPublish(
    Envelope envelope, {
    int? attempt,
    String? sender,
  }) {
    return StemSignals.beforeTaskPublish.emit(
      BeforeTaskPublishPayload(
        envelope: envelope,
        attempt: attempt ?? envelope.attempt,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the after-task-publish signal.
  Future<void> afterTaskPublish(
    Envelope envelope, {
    int? attempt,
    String? taskId,
    String? sender,
  }) {
    return StemSignals.afterTaskPublish.emit(
      AfterTaskPublishPayload(
        envelope: envelope,
        attempt: attempt ?? envelope.attempt,
        taskId: taskId ?? envelope.id,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-received signal.
  Future<void> taskReceived(
    Envelope envelope,
    WorkerInfo worker, {
    String? sender,
  }) {
    return StemSignals.taskReceived.emit(
      TaskReceivedPayload(envelope: envelope, worker: worker),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-prerun signal.
  Future<void> taskPrerun(
    Envelope envelope,
    WorkerInfo worker,
    TaskContext context, {
    String? sender,
  }) {
    return StemSignals.taskPrerun.emit(
      TaskPrerunPayload(envelope: envelope, worker: worker, context: context),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-postrun signal.
  Future<void> taskPostrun(
    Envelope envelope,
    WorkerInfo worker,
    TaskContext context, {
    required Object? result,
    required TaskState state,
    String? sender,
  }) {
    return StemSignals.taskPostrun.emit(
      TaskPostrunPayload(
        envelope: envelope,
        worker: worker,
        context: context,
        result: result,
        state: state,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-retry signal.
  Future<void> taskRetry(
    Envelope envelope,
    WorkerInfo worker, {
    required Object reason,
    required DateTime nextRetryAt,
    String? sender,
  }) {
    return StemSignals.taskRetry.emit(
      TaskRetryPayload(
        envelope: envelope,
        worker: worker,
        reason: reason,
        nextRetryAt: nextRetryAt,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-succeeded signal.
  Future<void> taskSucceeded(
    Envelope envelope,
    WorkerInfo worker, {
    required Object? result,
    String? sender,
  }) {
    return StemSignals.taskSucceeded.emit(
      TaskSuccessPayload(envelope: envelope, worker: worker, result: result),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-failed signal.
  Future<void> taskFailed(
    Envelope envelope,
    WorkerInfo worker, {
    required Object error,
    StackTrace? stackTrace,
    String? sender,
  }) {
    return StemSignals.taskFailed.emit(
      TaskFailurePayload(
        envelope: envelope,
        worker: worker,
        error: error,
        stackTrace: stackTrace,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the task-revoked signal.
  Future<void> taskRevoked(
    Envelope envelope,
    WorkerInfo worker, {
    required String reason,
    String? sender,
  }) {
    return StemSignals.taskRevoked.emit(
      TaskRevokedPayload(envelope: envelope, worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-init signal.
  Future<void> workerInit(WorkerInfo worker, {String? reason, String? sender}) {
    return StemSignals.workerInit.emit(
      WorkerLifecyclePayload(worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-ready signal.
  Future<void> workerReady(
    WorkerInfo worker, {
    String? reason,
    String? sender,
  }) {
    return StemSignals.workerReady.emit(
      WorkerLifecyclePayload(worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-stopping signal.
  Future<void> workerStopping(
    WorkerInfo worker, {
    String? reason,
    String? sender,
  }) {
    return StemSignals.workerStopping.emit(
      WorkerLifecyclePayload(worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-shutdown signal.
  Future<void> workerShutdown(
    WorkerInfo worker, {
    String? reason,
    String? sender,
  }) {
    return StemSignals.workerShutdown.emit(
      WorkerLifecyclePayload(worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-heartbeat signal.
  Future<void> workerHeartbeat(
    WorkerInfo worker,
    DateTime timestamp, {
    String? sender,
  }) {
    return StemSignals.workerHeartbeat.emit(
      WorkerHeartbeatPayload(worker: worker, timestamp: timestamp),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the worker-child-lifecycle signal.
  Future<void> workerChildLifecycle(
    WorkerInfo worker,
    int isolateId, {
    required bool initializing,
    String? sender,
  }) {
    final payload = WorkerChildLifecyclePayload(
      worker: worker,
      isolateId: isolateId,
    );
    final effectiveSender = _senderOverride(sender);
    if (initializing) {
      return StemSignals.workerChildInit.emit(payload, sender: effectiveSender);
    }
    return StemSignals.workerChildShutdown.emit(
      payload,
      sender: effectiveSender,
    );
  }

  /// Emits the schedule-entry-due signal.
  Future<void> scheduleEntryDue(
    ScheduleEntry entry,
    DateTime tickAt, {
    String? sender,
  }) {
    return StemSignals.scheduleEntryDue.emit(
      ScheduleEntryDuePayload(entry: entry, tickAt: tickAt),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the schedule-entry-dispatched signal.
  Future<void> scheduleEntryDispatched(
    ScheduleEntry entry, {
    required DateTime scheduledFor,
    required DateTime executedAt,
    required Duration drift,
    String? sender,
  }) {
    return StemSignals.scheduleEntryDispatched.emit(
      ScheduleEntryDispatchedPayload(
        entry: entry,
        scheduledFor: scheduledFor,
        executedAt: executedAt,
        drift: drift,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the schedule-entry-failed signal.
  Future<void> scheduleEntryFailed(
    ScheduleEntry entry, {
    required DateTime scheduledFor,
    required Object error,
    required StackTrace stackTrace,
    String? sender,
  }) {
    return StemSignals.scheduleEntryFailed.emit(
      ScheduleEntryFailedPayload(
        entry: entry,
        scheduledFor: scheduledFor,
        error: error,
        stackTrace: stackTrace,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the control-command-received signal.
  Future<void> controlCommandReceived(
    WorkerInfo worker,
    ControlCommandMessage command, {
    String? sender,
  }) {
    return StemSignals.controlCommandReceived.emit(
      ControlCommandReceivedPayload(worker: worker, command: command),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the control-command-completed signal.
  Future<void> controlCommandCompleted(
    WorkerInfo worker,
    ControlCommandMessage command, {
    required String status,
    Map<String, Object?>? response,
    Map<String, Object?>? error,
    String? sender,
  }) {
    return StemSignals.controlCommandCompleted.emit(
      ControlCommandCompletedPayload(
        worker: worker,
        command: command,
        status: status,
        response: response,
        error: error,
      ),
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-started signal.
  Future<void> workflowRunStarted(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunStarted.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-suspended signal.
  Future<void> workflowRunSuspended(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunSuspended.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-resumed signal.
  Future<void> workflowRunResumed(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunResumed.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-completed signal.
  Future<void> workflowRunCompleted(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunCompleted.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-failed signal.
  Future<void> workflowRunFailed(WorkflowRunPayload payload, {String? sender}) {
    return StemSignals.workflowRunFailed.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  /// Emits the workflow-run-cancelled signal.
  Future<void> workflowRunCancelled(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunCancelled.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }
}
