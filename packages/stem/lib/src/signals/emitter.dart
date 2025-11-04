import '../control/control_messages.dart';
import '../core/contracts.dart';
import '../core/envelope.dart';
import 'payloads.dart';
import 'stem_signals.dart';

/// Helper used by coordinators, workers, and middleware to emit strongly
/// typed Stem signals without duplicating payload construction.
class StemSignalEmitter {
  const StemSignalEmitter({this.defaultSender});

  /// Optional sender identifier applied when no explicit sender is supplied.
  final String? defaultSender;

  String? _senderOverride(String? sender) => sender ?? defaultSender;

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

  Future<void> workerInit(WorkerInfo worker, {String? reason, String? sender}) {
    return StemSignals.workerInit.emit(
      WorkerLifecyclePayload(worker: worker, reason: reason),
      sender: _senderOverride(sender),
    );
  }

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

  Future<void> workerChildLifecycle(
    WorkerInfo worker,
    int isolateId, {
    String? sender,
    required bool initializing,
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

  Future<void> workflowRunStarted(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunStarted.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  Future<void> workflowRunSuspended(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunSuspended.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  Future<void> workflowRunResumed(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunResumed.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  Future<void> workflowRunCompleted(
    WorkflowRunPayload payload, {
    String? sender,
  }) {
    return StemSignals.workflowRunCompleted.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

  Future<void> workflowRunFailed(WorkflowRunPayload payload, {String? sender}) {
    return StemSignals.workflowRunFailed.emit(
      payload,
      sender: _senderOverride(sender),
    );
  }

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
