import 'run_state.dart';
import 'workflow_status.dart';
import 'workflow_step_entry.dart';

/// Persistent storage for workflow runs, checkpoints, and suspensions.
abstract class WorkflowStore {
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
  });

  Future<RunState?> get(String runId);

  Future<T?> readStep<T>(String runId, String stepName);

  Future<void> saveStep<T>(String runId, String stepName, T value);

  /// Suspends [runId] until the given [when].
  ///
  /// Implementations should persist [data] so it becomes available as
  /// `resumeData` when the run wakes up.
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  });

  /// Suspends [runId] while awaiting an event with [topic].
  ///
  /// If [deadline] is provided, the run should be considered due at that time
  /// even if an event is never received.
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  });

  Future<void> markRunning(String runId, {String? stepName});

  Future<void> markCompleted(String runId, Object? result);

  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  });

  /// Clears suspension metadata when the run is ready to execute again.
  ///
  /// Any [data] value becomes the `resumeData` payload exposed to the next
  /// step invocation.
  Future<void> markResumed(String runId, {Map<String, Object?>? data});

  /// Returns run identifiers whose wake-up time is at or before [now].
  Future<List<String>> dueRuns(DateTime now, {int limit = 256});

  /// Returns run identifiers currently suspended on [topic].
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256});

  /// Transitions the run to [WorkflowStatus.cancelled].
  Future<void> cancel(String runId, {String? reason});

  /// Rewinds a run so the given [stepName] (and subsequent steps) will execute
  /// again on the next resume.
  Future<void> rewindToStep(String runId, String stepName);

  /// Returns recent runs filtered by [workflow] and/or [status].
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
  });

  /// Returns persisted step results for inspection/debugging.
  Future<List<WorkflowStepEntry>> listSteps(String runId);
}
