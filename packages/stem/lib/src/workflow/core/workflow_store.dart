import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_step_entry.dart';
import 'package:stem/src/workflow/core/workflow_watcher.dart';

/// Persistent storage for workflow runs, checkpoints, and suspensions.
abstract class WorkflowStore {
  /// Creates a new workflow run record and returns its run id.
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? runId,
    String? parentRunId,
    Duration? ttl,

    /// Optional cancellation policy that will be enforced by the runtime.
    WorkflowCancellationPolicy? cancellationPolicy,
  });

  /// Fetches the persisted run state for [runId], or `null` if missing.
  Future<RunState?> get(String runId);

  /// Reads the persisted checkpoint value for [stepName].
  Future<T?> readStep<T>(String runId, String stepName);

  /// Saves a checkpoint for [stepName] and refreshes the run heartbeat.
  ///
  /// Implementations MUST atomically persist the checkpoint and update the
  /// run's last-modified timestamp so operators can identify active ownership.
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

  /// Registers a durable watcher for [topic] so the runtime can resume
  /// [stepName] when an event is emitted.
  ///
  /// Implementations MUST persist the suspension metadata and watcher record
  /// atomically so an incoming payload can be recorded even if no worker is
  /// currently running. When a [deadline] is provided the run should surface in
  /// [dueRuns] once the deadline passes so timeouts can resume the workflow.
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  });

  /// Resolves watchers listening on [topic], persisting [payload] and marking
  /// runs ready to resume atomically. Returns the resolved watchers so the
  /// runtime can enqueue follow-up work.
  ///
  /// The returned [WorkflowWatcherResolution] objects MUST include the merged
  /// suspension metadata (`resumeData`) that will be exposed to
  /// `FlowContext.takeResumeData`/`WorkflowScriptStepContext.takeResumeData`.
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  });

  /// Lists outstanding watchers for [topic] (primarily for operator tooling).
  /// The metadata helps CLIs and dashboards explain why a run is waiting.
  Future<List<WorkflowWatcher>> listWatchers(String topic, {int limit = 256});

  /// Marks the run as running and optionally sets the active [stepName].
  Future<void> markRunning(String runId, {String? stepName});

  /// Marks the run as completed with the provided [result].
  Future<void> markCompleted(String runId, Object? result);

  /// Marks the run as failed and records [error] and [stack].
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

  /// Attempts to claim a run for execution with a lease.
  ///
  /// Returns `true` when the claim succeeds, or `false` if another worker
  /// holds an active lease.
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  });

  /// Renews the lease for [runId] when owned by [ownerId].
  ///
  /// Returns `true` when the lease is extended, or `false` if ownership
  /// has changed or the run is no longer runnable.
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  });

  /// Releases the lease on [runId] when owned by [ownerId].
  Future<void> releaseRun(String runId, {required String ownerId});

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
    int offset = 0,
  });

  /// Returns runnable run identifiers filtered by status and lease
  /// availability.
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  });

  /// Returns persisted step results for inspection/debugging.
  Future<List<WorkflowStepEntry>> listSteps(String runId);
}

/// Optional capability for stores that can fence workflow execution attempts.
///
/// A store implementing this interface must generate a fresh
/// [WorkflowExecutionClaim.executionId] for
/// every successful claim and require that id for lease mutation and terminal
/// failure finalization. This prevents a stale delivery from mutating a newer
/// execution owned by the same runtime.
///
/// A claim rejects any active lease, including one with the same logical owner.
/// Release retains execution identity for failure recovery; a new claim or an
/// explicit resume/rewind invalidates the old identity. Legacy owner-only lease
/// operations must not renew or release tokenized executions.
///
/// This capability fences lease operations and terminal-failure finalization.
/// It does not make every [WorkflowStore] mutation conditional or make external
/// side effects exactly-once.
abstract interface class FencedWorkflowStore {
  /// Atomically claims [runId], returning its unique execution identity.
  Future<WorkflowExecutionClaim?> claimRunExecution(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  });

  /// Renews a still-active, unexpired lease only when [executionId] is current.
  Future<bool> renewRunExecution(
    String runId, {
    required String executionId,
    Duration leaseDuration = const Duration(seconds: 30),
  });

  /// Releases a lease only when [executionId] is still current.
  Future<void> releaseRunExecution(
    String runId, {
    required String executionId,
  });

  /// Records an error only if the captured execution is still current.
  ///
  /// With [terminal] false, only error metadata is changed; status and lease
  /// remain unchanged so the worker's retry policy can decide the outcome.
  /// With [terminal] true, the run transitions to failed and loses its lease.
  Future<TerminalFailureResult> markFailedForExecution(
    String runId, {
    required String executionId,
    required Object error,
    required StackTrace stack,
    bool terminal = true,
  });
}

/// Identity returned by a fenced workflow claim.
class WorkflowExecutionClaim {
  /// Creates a workflow execution identity.
  const WorkflowExecutionClaim({
    required this.runId,
    required this.executionId,
    required this.ownerId,
    required this.leaseExpiresAt,
  });

  /// Rehydrates a claim from a serialized map.
  factory WorkflowExecutionClaim.fromJson(Map<String, Object?> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid workflow execution claim field: $key');
      }
      return value;
    }

    final expiry = DateTime.tryParse(field('leaseExpiresAt'));
    if (expiry == null) {
      throw const FormatException('Invalid workflow execution claim expiry');
    }
    return WorkflowExecutionClaim(
      runId: field('runId'),
      executionId: field('executionId'),
      ownerId: field('ownerId'),
      leaseExpiresAt: expiry,
    );
  }

  /// Workflow run whose execution was claimed.
  final String runId;

  /// Opaque identity of this particular claim, not merely its logical owner.
  final String executionId;

  /// Logical runtime or worker requesting the claim.
  final String ownerId;

  /// Lease deadline at claim time.
  final DateTime leaseExpiresAt;

  /// Serializes this claim for trusted task metadata.
  Map<String, Object?> toJson() => {
    'runId': runId,
    'executionId': executionId,
    'ownerId': ownerId,
    'leaseExpiresAt': leaseExpiresAt.toIso8601String(),
  };
}

/// Result of a fenced terminal-failure attempt.
enum TerminalFailureResult {
  /// The current execution's error update was applied.
  applied,

  /// The same execution had already transitioned the run.
  alreadyFailedForExecution,

  /// A newer execution or terminal state superseded this callback.
  superseded,
}
