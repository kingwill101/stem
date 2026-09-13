import 'dart:math' as math;

import 'package:stem/src/core/contracts.dart' show TaskRetryVeto;
import 'package:stem/src/workflow/core/run_state.dart';

/// Serializable retry policy for one logical checkpoint or compensation.
///
/// [maxAttempts] includes the first attempt. Queue delivery counts do not
/// reset this budget. Jitter and executable retry predicates are not persisted.
final class WorkflowRetryPolicy {
  /// Creates fixed delays when [multiplier] is one, exponential otherwise.
  const WorkflowRetryPolicy({
    this.maxAttempts = 1,
    this.delay = Duration.zero,
    this.multiplier = 1,
    this.maxDelay = const Duration(minutes: 5),
  });

  /// Rejects malformed or invalid persisted policies.
  factory WorkflowRetryPolicy.fromJson(Map<String, Object?> json) {
    if (json['maxAttempts'] is! int ||
        json['delayMicros'] is! int ||
        json['maxDelayMicros'] is! int ||
        json['multiplier'] is! num) {
      throw const FormatException('Invalid workflow retry policy.');
    }
    final policy = WorkflowRetryPolicy(
      maxAttempts: json['maxAttempts']! as int,
      delay: Duration(microseconds: json['delayMicros']! as int),
      multiplier: (json['multiplier']! as num).toDouble(),
      maxDelay: Duration(microseconds: json['maxDelayMicros']! as int),
    );
    if (!policy._valid) {
      throw const FormatException('Invalid workflow retry policy.');
    }
    return policy;
  }

  /// Total allowed attempts, including abandoned attempts after a crash.
  final int maxAttempts;

  /// Delay after the first failed attempt.
  final Duration delay;

  /// Exponential multiplier, at least one.
  final double multiplier;

  /// Upper bound for every retry delay.
  final Duration maxDelay;

  /// Validates in release builds as well as debug builds.
  void validate() {
    if (!_valid) {
      throw ArgumentError('Invalid workflow retry policy.');
    }
  }

  bool get _valid =>
      maxAttempts >= 1 &&
      !delay.isNegative &&
      !maxDelay.isNegative &&
      multiplier.isFinite &&
      multiplier >= 1;

  /// Returns a bounded delay after the one-based failed [attempt].
  Duration delayAfter(int attempt) {
    validate();
    if (attempt < 1) throw ArgumentError.value(attempt, 'attempt');
    final micros = delay == Duration.zero
        ? 0
        : (delay.inMicroseconds * math.pow(multiplier, attempt - 1))
              .clamp(0, maxDelay.inMicroseconds)
              .toInt();
    return Duration(microseconds: micros);
  }

  /// Encodes without losing sub-millisecond precision.
  Map<String, Object?> toJson() {
    validate();
    return {
      'maxAttempts': maxAttempts,
      'delayMicros': delay.inMicroseconds,
      'multiplier': multiplier,
      'maxDelayMicros': maxDelay.inMicroseconds,
    };
  }
}

/// Separate journal namespaces; neither is an ordinary checkpoint.
enum WorkflowJournalKind {
  /// Logical step attempt accounting.
  step,

  /// Reverse-order cleanup accounting.
  compensation,
}

/// A logical checkpoint exhausted its persisted attempt budget.
class WorkflowStepRetryExhausted implements Exception, TaskRetryVeto {
  /// Creates an inspectable failure that can be reconstructed after restart.
  const WorkflowStepRetryExhausted(
    this.runId,
    this.stepName,
    this.attempts,
    this.lastError,
  );

  /// Workflow run identifier.
  final String runId;

  /// Persisted checkpoint name.
  final String stepName;

  /// Total attempts consumed.
  final int attempts;

  /// Last persisted failure details or an abandoned-claim diagnostic.
  final Object? lastError;

  @override
  String toString() =>
      'Workflow $runId checkpoint $stepName exhausted $attempts attempts: '
      '$lastError';
}

/// Cleanup exhausted its durable budget and requires operator intervention.
class WorkflowCompensationRetryExhausted implements Exception, TaskRetryVeto {
  /// Creates a failure without resetting the persisted cleanup attempt count.
  const WorkflowCompensationRetryExhausted(
    this.runId,
    this.stepName,
    this.attempts,
    this.lastError,
  );

  /// Failed workflow run.
  final String runId;

  /// Checkpoint whose cleanup did not complete.
  final String stepName;

  /// Lifetime cleanup attempts consumed.
  final int attempts;

  /// Persisted cleanup failure.
  final Object? lastError;

  @override
  String toString() =>
      'Workflow $runId cleanup for $stepName exhausted $attempts attempts: '
      '$lastError';
}

/// One versioned journal record. [name] is the exact persisted checkpoint name.
final class WorkflowJournalEntry {
  /// Creates a snapshot; revision zero represents a record not yet persisted.
  WorkflowJournalEntry({
    required this.runId,
    required this.kind,
    required this.name,
    required this.revision,
    required Map<String, Object?> data,
    this.position,
  }) : data = Map.unmodifiable(data);

  /// Workflow run ID.
  final String runId;

  /// Journal namespace.
  final WorkflowJournalKind kind;

  /// Exact checkpoint name, including an iteration suffix when present.
  final String name;

  /// Compare-and-set revision, incremented on each successful write.
  final int revision;

  /// Serializable protocol state; encoded user values obey backend constraints.
  final Map<String, Object?> data;

  /// Successful completion order, assigned atomically for compensation records.
  final int? position;
}

/// Run identity and one journal record read for an optimistic state transition.
final class WorkflowJournalSnapshot {
  /// Creates a read snapshot. A missing record has [entry] equal to null.
  const WorkflowJournalSnapshot({required this.run, this.entry});

  /// Current run state. Writers must recheck its execution identity atomically.
  final RunState run;

  /// Current journal record, if any.
  final WorkflowJournalEntry? entry;
}

/// Compensation metadata committed together with a successful checkpoint.
final class WorkflowCompensationRegistration {
  /// Creates a stable named registration with its encoded successful result.
  const WorkflowCompensationRegistration({
    required this.handler,
    required this.input,
    this.retryPolicy = const WorkflowRetryPolicy(),
  });

  /// Handler ID resolved from executable definitions after restart.
  final String handler;

  /// Encoded result snapshot, not a mutable closure capture.
  final Object? input;

  /// Independent compensation retry budget.
  final WorkflowRetryPolicy retryPolicy;

  /// Initial persisted state; never contains executable callbacks.
  Map<String, Object?> toJournalData() {
    if (handler.trim().isEmpty) {
      throw ArgumentError.value(handler, 'handler', 'Must not be empty.');
    }
    return {
      'version': 1,
      'state': 'pending',
      'handler': handler,
      'input': input,
      'policy': retryPolicy.toJson(),
      'attempts': 0,
    };
  }
}

/// Optional checkpoint write coupled atomically to a journal success write.
final class WorkflowJournalCheckpoint {
  /// Creates a checkpoint and optional compensation registration.
  const WorkflowJournalCheckpoint({required this.value, this.compensation});

  /// Encoded ordinary checkpoint value.
  final Object? value;

  /// Optional cleanup registration for this checkpoint.
  final WorkflowCompensationRegistration? compensation;
}

/// Optional versioned journal storage on the same store as workflow runs.
///
/// Records must not appear in ordinary checkpoint lists or cursor counts.
/// A write atomically checks the run execution ID, lifecycle status, and record
/// revision. Successful step writes may commit a checkpoint and compensation
/// registration in that same transaction. Implementations must reject partial
/// commits, including checkpoint writes when the journal CAS fails.
abstract interface class WorkflowJournalStore {
  /// Reads current run state and a record, or null if the run does not exist.
  Future<WorkflowJournalSnapshot?> readJournal(
    String runId,
    WorkflowJournalKind kind,
    String name,
  );

  /// Lists compensation records in descending successful completion order.
  Future<List<WorkflowJournalEntry>> listCompensations(String runId);

  /// Commits a revision and optional checkpoint, returning false on conflict.
  ///
  /// [WorkflowJournalEntry.revision] must equal [expectedRevision] + 1.
  /// Missing records have
  /// revision zero. Forward writes require a running run; compensation writes
  /// require a failed run. Both require the exact [executionId]. A compensation
  /// registration gets a unique monotonically increasing completion position.
  ///
  /// Ordinary administrative rewind must delete journal records for discarded
  /// checkpoints and invalidate existing execution/compensation claims.
  Future<bool> commitJournal(
    WorkflowJournalEntry entry, {
    required int expectedRevision,
    required String executionId,
    WorkflowJournalCheckpoint? checkpoint,
  });
}
