import 'package:collection/collection.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:stem/src/workflow/core/workflow_journal.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:uuid/uuid.dart';

/// A journal claim lost its run identity, record version, or operation token.
class WorkflowJournalConflict implements Exception {
  /// Describes the rejected mutation without changing persisted state.
  const WorkflowJournalConflict(this.message);

  /// Diagnostic reason.
  final String message;

  @override
  String toString() => 'WorkflowJournalConflict: $message';
}

/// State-machine result. A running record is executable only if acquired.
class WorkflowJournalAttempt {
  /// Wraps the committed/read record.
  WorkflowJournalAttempt(this.entry, {this.acquired = false}) {
    if (entry.data['version'] != 1 ||
        entry.data['attempts'] is! int ||
        attempts < 0 ||
        entry.data['state'] is! String ||
        !const {
          'pending',
          'running',
          'waiting',
          'completed',
          'exhausted',
        }.contains(state)) {
      throw const FormatException('Invalid workflow journal state.');
    }
  }

  /// Current persisted record.
  final WorkflowJournalEntry entry;

  /// Whether this call acquired the operation, rather than finding it busy.
  final bool acquired;

  /// Persisted operation state.
  String get state => entry.data['state']! as String;

  /// Durable count, including abandoned claims.
  int get attempts => entry.data['attempts']! as int;

  /// Current attempt token, present for an acquired claim.
  String? get token => entry.data['token'] as String?;

  /// Run identity under which this attempt was claimed.
  String? get executionId => entry.data['executionId'] as String?;

  /// Persisted absolute retry time or active compensation lease expiry.
  DateTime? get readyAt {
    final raw = state == 'running'
        ? entry.data['leaseUntil']
        : entry.data['nextAttemptAt'];
    if (raw == null) return null;
    if (raw is! String || DateTime.tryParse(raw) == null) {
      throw const FormatException('Invalid workflow journal timestamp.');
    }
    return DateTime.parse(raw);
  }

  /// Persisted retry budget and timing policy.
  WorkflowRetryPolicy get policy => WorkflowRetryPolicy.fromJson(
    (entry.data['policy']! as Map).cast<String, Object?>(),
  );
}

/// Pure journal transitions around storage CAS; never executes user callbacks.
class WorkflowJournalController {
  /// Uses the runtime's clock and the store backing the same workflow runs.
  WorkflowJournalController(this.store, this.clock);

  /// Durable journal capability.
  final WorkflowJournalStore store;

  /// Time source used when persisting authoritative ETAs.
  final WorkflowClock clock;

  Future<WorkflowJournalSnapshot> _read(
    String runId,
    WorkflowJournalKind kind,
    String name,
    String executionId,
  ) async {
    final snapshot = await store.readJournal(runId, kind, name);
    final status = kind == WorkflowJournalKind.step
        ? WorkflowStatus.running
        : WorkflowStatus.failed;
    if (snapshot == null ||
        snapshot.run.executionId != executionId ||
        snapshot.run.status != status) {
      throw const WorkflowJournalConflict(
        'Workflow execution is no longer current.',
      );
    }
    return snapshot;
  }

  /// Acquires a checkpoint attempt without resetting its durable budget.
  Future<WorkflowJournalAttempt> claimStep(
    String runId,
    String name,
    String executionId,
    WorkflowRetryPolicy policy,
  ) => _claim(
    runId,
    WorkflowJournalKind.step,
    name,
    executionId,
    policy: policy,
  );

  Future<WorkflowJournalAttempt> _claim(
    String runId,
    WorkflowJournalKind kind,
    String name,
    String executionId, {
    WorkflowRetryPolicy? policy,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    policy?.validate();
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
    for (var conflict = 0; conflict < 8; conflict++) {
      final snapshot = await _read(runId, kind, name, executionId);
      final previous = snapshot.entry;
      final old = previous == null ? null : WorkflowJournalAttempt(previous);
      if (kind == WorkflowJournalKind.compensation && old == null) {
        throw const WorkflowJournalConflict(
          'Compensation registration disappeared.',
        );
      }
      final selected = old?.policy ?? policy!;
      if (policy != null &&
          old != null &&
          !const DeepCollectionEquality().equals(
            policy.toJson(),
            selected.toJson(),
          )) {
        throw StateError(
          'Retry policy changed for persisted checkpoint $name.',
        );
      }
      if (old != null) {
        if (old.state == 'completed' || old.state == 'exhausted') return old;
        if (kind == WorkflowJournalKind.compensation &&
            old.executionId != null &&
            old.executionId != executionId) {
          throw const WorkflowJournalConflict(
            'Compensation belongs to a prior failure.',
          );
        }
        if (old.state == 'waiting' && old.readyAt!.isAfter(clock.now())) {
          return old;
        }
        if (old.state == 'running') {
          if (kind == WorkflowJournalKind.step &&
              old.executionId == executionId) {
            return old;
          }
          if (kind == WorkflowJournalKind.compensation &&
              old.readyAt!.isAfter(clock.now())) {
            return old;
          }
        }
      }
      final attempts = old?.attempts ?? 0;
      final exhausted = attempts >= selected.maxAttempts;
      final data = <String, Object?>{
        ...?previous?.data,
        'version': 1,
        'state': exhausted ? 'exhausted' : 'running',
        'attempts': exhausted ? attempts : attempts + 1,
        'policy': selected.toJson(),
        'executionId': executionId,
        'token': const Uuid().v7(),
        'nextAttemptAt': null,
        'leaseUntil': kind == WorkflowJournalKind.compensation && !exhausted
            ? clock.now().add(leaseDuration).toUtc().toIso8601String()
            : null,
        if (exhausted && previous?.data['lastError'] == null)
          'lastError': const {
            'error': 'Attempt ended before checkpoint completion.',
          },
      };
      final entry = WorkflowJournalEntry(
        runId: runId,
        kind: kind,
        name: name,
        revision: (previous?.revision ?? 0) + 1,
        position: previous?.position,
        data: data,
      );
      if (await store.commitJournal(
        entry,
        expectedRevision: previous?.revision ?? 0,
        executionId: executionId,
      )) {
        return WorkflowJournalAttempt(entry, acquired: !exhausted);
      }
    }
    throw const WorkflowJournalConflict(
      'Journal contention exceeded retry limit.',
    );
  }

  /// Commits the value and cleanup registration in the journal transaction.
  Future<void> completeStep(
    WorkflowJournalAttempt attempt,
    Object? value, {
    WorkflowCompensationRegistration? compensation,
  }) async {
    await _change(
      attempt,
      {
        'state': 'completed',
        'value': value,
        'lastError': null,
        'nextAttemptAt': null,
      },
      checkpoint: WorkflowJournalCheckpoint(
        value: value,
        compensation: compensation,
      ),
    );
  }

  /// Records failure and its absolute ETA, or exhausts the persisted budget.
  Future<WorkflowJournalAttempt> fail(
    WorkflowJournalAttempt attempt,
    Object error,
    StackTrace stack,
  ) async {
    final policy = attempt.policy;
    final exhausted = attempt.attempts >= policy.maxAttempts;
    final updated = await _change(attempt, {
      'state': exhausted ? 'exhausted' : 'waiting',
      'nextAttemptAt': exhausted
          ? null
          : clock
                .now()
                .add(policy.delayAfter(attempt.attempts))
                .toUtc()
                .toIso8601String(),
      'leaseUntil': null,
      'lastError': {'error': error.toString(), 'stack': stack.toString()},
    });
    return WorkflowJournalAttempt(updated);
  }

  Future<WorkflowJournalEntry> _change(
    WorkflowJournalAttempt attempt,
    Map<String, Object?> changes, {
    WorkflowJournalCheckpoint? checkpoint,
  }) async {
    if (!attempt.acquired ||
        attempt.token == null ||
        attempt.executionId == null) {
      throw const WorkflowJournalConflict('Operation was not acquired.');
    }
    for (var conflict = 0; conflict < 8; conflict++) {
      final snapshot = await _read(
        attempt.entry.runId,
        attempt.entry.kind,
        attempt.entry.name,
        attempt.executionId!,
      );
      final current = snapshot.entry;
      if (current == null ||
          current.data['state'] != 'running' ||
          current.data['token'] != attempt.token) {
        throw const WorkflowJournalConflict(
          'Operation token is no longer current.',
        );
      }
      final next = WorkflowJournalEntry(
        runId: current.runId,
        kind: current.kind,
        name: current.name,
        revision: current.revision + 1,
        position: current.position,
        data: {...current.data, ...changes},
      );
      if (await store.commitJournal(
        next,
        expectedRevision: current.revision,
        executionId: attempt.executionId!,
        checkpoint: checkpoint,
      )) {
        return next;
      }
    }
    throw const WorkflowJournalConflict(
      'Journal contention exceeded retry limit.',
    );
  }

  /// Claims only the next reverse-order operation; pending/exhausted work blocks
  /// earlier cleanup rather than silently running it out of order.
  Future<WorkflowJournalAttempt?> claimCompensation(
    String runId,
    String failedExecutionId, {
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final entries = await store.listCompensations(runId);
    for (final entry in entries) {
      final attempt = WorkflowJournalAttempt(entry);
      if (attempt.state == 'completed') continue;
      return _claim(
        runId,
        WorkflowJournalKind.compensation,
        entry.name,
        failedExecutionId,
        leaseDuration: leaseDuration,
      );
    }
    return null;
  }

  /// Completes a claimed cleanup operation without re-running prior successes.
  Future<void> completeCompensation(WorkflowJournalAttempt attempt) async {
    await _change(attempt, {
      'state': 'completed',
      'leaseUntil': null,
      'nextAttemptAt': null,
    });
  }

  /// Renews a cleanup lease using its independent operation token.
  Future<void> renewCompensation(
    WorkflowJournalAttempt attempt,
    Duration leaseDuration,
  ) async {
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
    await _change(attempt, {
      'leaseUntil': clock.now().add(leaseDuration).toUtc().toIso8601String(),
    });
  }

  /// Explicit operator budget extension; lifetime attempt counts are retained.
  Future<void> extendCompensationBudget(
    String runId,
    String name,
    String failedExecutionId,
    int additionalAttempts,
  ) async {
    if (additionalAttempts < 1) {
      throw ArgumentError.value(additionalAttempts, 'additionalAttempts');
    }
    final snapshot = await _read(
      runId,
      WorkflowJournalKind.compensation,
      name,
      failedExecutionId,
    );
    final old = snapshot.entry;
    if (old == null) throw StateError('Compensation $name is not registered.');
    final attempt = WorkflowJournalAttempt(old);
    if (attempt.state != 'exhausted') return;
    final policy = attempt.policy;
    final next = WorkflowJournalEntry(
      runId: runId,
      kind: old.kind,
      name: name,
      revision: old.revision + 1,
      position: old.position,
      data: {
        ...old.data,
        'state': 'pending',
        'nextAttemptAt': null,
        'policy': WorkflowRetryPolicy(
          maxAttempts: attempt.attempts + additionalAttempts,
          delay: policy.delay,
          multiplier: policy.multiplier,
          maxDelay: policy.maxDelay,
        ).toJson(),
      },
    );
    if (!await store.commitJournal(
      next,
      expectedRevision: old.revision,
      executionId: failedExecutionId,
    )) {
      throw const WorkflowJournalConflict(
        'Compensation changed during retry request.',
      );
    }
  }
}
