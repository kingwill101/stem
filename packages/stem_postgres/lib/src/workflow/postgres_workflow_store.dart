// Public constructor names intentionally initialize private implementation
// fields to preserve the package API.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/workflow_models.dart';
import 'package:uuid/uuid.dart';

/// PostgreSQL-backed [WorkflowStore] implementation using ormed ORM.
class PostgresWorkflowStore
    implements
        WorkflowStore,
        WorkflowTerminalStore,
        FencedWorkflowStore,
        WorkflowJournalStore {
  PostgresWorkflowStore._(
    this._connections, {
    required this.namespace,
    required WorkflowClock clock,
    Uuid? uuid,
  }) : _clock = clock,
       _uuid = uuid ?? const Uuid();

  final PostgresConnections _connections;

  /// Creates a workflow store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<PostgresWorkflowStore> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    Uuid? uuid,
    WorkflowClock clock = const SystemWorkflowClock(),
    bool runMigrations = true,
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.openWithDataSource(
      dataSource,
      runMigrations: runMigrations,
    );
    return PostgresWorkflowStore._(
      connections,
      namespace: resolvedNamespace,
      clock: clock,
      uuid: uuid,
    );
  }

  /// Namespace used to scope workflow resources.
  final String namespace;
  final Uuid _uuid;
  final WorkflowClock _clock;

  Map<String, Object?> _prepareSuspensionData(
    Map<String, Object?>? source, {
    DateTime? resumeAt,
    DateTime? deadline,
    String? topic,
  }) {
    final result = <String, Object?>{};
    if (source != null) {
      result.addAll(source);
    }
    if (resumeAt != null && !result.containsKey('resumeAt')) {
      result['resumeAt'] = resumeAt.toIso8601String();
    }
    if (deadline != null && !result.containsKey('deadline')) {
      result['deadline'] = deadline.toIso8601String();
    }
    if (topic != null && topic.isNotEmpty && !result.containsKey('topic')) {
      result['topic'] = topic;
    }
    return result;
  }

  /// Connects to a PostgreSQL database and ensures workflow tables exist.
  static Future<PostgresWorkflowStore> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    String? applicationName,
    TlsConfig? tls,
    Uuid? uuid,
    WorkflowClock clock = const SystemWorkflowClock(),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresWorkflowStore._(
      connections,
      namespace: resolvedNamespace,
      clock: clock,
      uuid: uuid,
    );
  }

  /// Closes the workflow store and releases database resources.
  Future<void> close() async {
    await _connections.close();
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? runId,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final id = (runId != null && runId.trim().isNotEmpty)
        ? runId.trim()
        : _uuid.v7();
    final now = _clock.now().toUtc();
    final workflowName = workflow;

    await _connections.runInTransaction((ctx) async {
      final run = $StemWorkflowRun(
        id: id,
        namespace: namespace,
        workflow: workflowName,
        status: WorkflowStatus.running.name,
        params: jsonEncode(params),
        cancellationPolicy: cancellationPolicy == null
            ? null
            : jsonEncode(cancellationPolicy.toJson()),
        createdAt: now,
        updatedAt: now,
      );

      await ctx.repository<$StemWorkflowRun>().insert(run);
    });

    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    return _readRunState(_connections.context, runId);
  }

  @override
  Future<WorkflowJournalSnapshot?> readJournal(
    String runId,
    WorkflowJournalKind kind,
    String name,
  ) async {
    final run = await _readRunState(_connections.context, runId);
    if (run == null) return null;
    final rows = await _connections.context.driver.queryRaw(
      '''
SELECT revision, position, data
FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ? AND kind = ? AND name = ?
''',
      [namespace, runId, kind.name, name],
    );
    return WorkflowJournalSnapshot(
      run: run,
      entry: rows.isEmpty
          ? null
          : _journalEntry(rows.single, runId, kind, name),
    );
  }

  @override
  Future<List<WorkflowJournalEntry>> listCompensations(String runId) async {
    final rows = await _connections.context.driver.queryRaw(
      '''
SELECT name, revision, position, data
FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ? AND kind = 'compensation'
ORDER BY position DESC
''',
      [namespace, runId],
    );
    return rows
        .map(
          (row) => _journalEntry(
            row,
            runId,
            WorkflowJournalKind.compensation,
            row['name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> commitJournal(
    WorkflowJournalEntry entry, {
    required int expectedRevision,
    required String executionId,
    WorkflowJournalCheckpoint? checkpoint,
  }) async {
    if (entry.revision != expectedRevision + 1) return false;
    if (entry.runId.trim().isEmpty || entry.name.trim().isEmpty) return false;
    if (checkpoint != null && entry.kind != WorkflowJournalKind.step) {
      return false;
    }
    final requiredStatus = entry.kind == WorkflowJournalKind.step
        ? WorkflowStatus.running
        : WorkflowStatus.failed;

    return _connections.runInTransaction((ctx) async {
      // The guarded update both fences the caller and takes the run row lock.
      final locked = await ctx.driver.queryRaw(
        '''
UPDATE stem_workflow_runs
SET updated_at = updated_at
WHERE namespace = ? AND id = ? AND execution_id = ? AND status = ?
RETURNING id
''',
        [namespace, entry.runId, executionId, requiredStatus.name],
      );
      if (locked.isEmpty) return false;

      final current = await ctx.driver.queryRaw(
        '''
SELECT revision, position
FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ? AND kind = ? AND name = ?
FOR UPDATE
''',
        [namespace, entry.runId, entry.kind.name, entry.name],
      );
      final actual = current.isEmpty ? 0 : _asInt(current.single['revision']);
      if (actual != expectedRevision) return false;
      // Compensation attempts advance an existing registration; they never
      // create a new record or acquire a new completion position.
      if (entry.kind == WorkflowJournalKind.compensation && current.isEmpty) {
        return false;
      }

      final position = entry.kind == WorkflowJournalKind.step
          ? null
          : _asInt(current.single['position']);

      await ctx.driver.executeRaw(
        '''
INSERT INTO stem_workflow_journal
  (namespace, run_id, kind, name, revision, position, data)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (namespace, run_id, kind, name)
DO UPDATE SET revision = EXCLUDED.revision, position = EXCLUDED.position,
              data = EXCLUDED.data
''',
        [
          namespace,
          entry.runId,
          entry.kind.name,
          entry.name,
          entry.revision,
          position,
          jsonEncode(entry.data),
        ],
      );

      // Checkpoints remain ordinary workflow steps; this is deliberately
      // performed in this transaction rather than calling public saveStep.
      if (checkpoint != null) {
        await _saveStepInTransaction(
          ctx,
          entry.runId,
          entry.name,
          checkpoint.value,
        );
        final registration = checkpoint.compensation;
        if (registration != null) {
          final next = await ctx.driver.queryRaw(
            '''
SELECT COALESCE(MAX(position), 0) + 1 AS position
FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ? AND kind = 'compensation'
''',
            [namespace, entry.runId],
          );
          await ctx.driver.executeRaw(
            '''
INSERT INTO stem_workflow_journal
  (namespace, run_id, kind, name, revision, position, data)
VALUES (?, ?, 'compensation', ?, 1, ?, ?)
ON CONFLICT (namespace, run_id, kind, name) DO NOTHING
''',
            [
              namespace,
              entry.runId,
              entry.name,
              _asInt(next.single['position']),
              jsonEncode(registration.toJournalData()),
            ],
          );
        }
      }
      await ctx.driver.executeRaw(
        'UPDATE stem_workflow_runs SET updated_at = ? '
        'WHERE namespace = ? AND id = ?',
        [_clock.now().toUtc(), namespace, entry.runId],
      );
      return true;
    }, operation: 'workflow.journal.commit');
  }

  Future<RunState?> _readRunState(QueryContext ctx, String runId) async {
    final run = await ctx
        .query<$StemWorkflowRun>()
        .whereEquals('id', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (run == null) return null;

    // Count distinct base step names for cursor
    final steps = await ctx
        .query<$StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .get();

    final baseSteps = <String>{};
    for (final step in steps) {
      baseSteps.add(_baseStepName(step.name));
    }

    return RunState(
      id: run.id,
      workflow: run.workflow,
      status: WorkflowStatus.values.firstWhere(
        (v) => v.name == run.status,
        orElse: () => WorkflowStatus.running,
      ),
      cursor: baseSteps.length,
      params: _decodeMap(run.params),
      result: _decodeValue(run.result),
      waitTopic: run.waitTopic,
      resumeAt: run.resumeAt,
      lastError: _decodeMap(run.lastError),
      suspensionData: _decodeMap(run.suspensionData),
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      ownerId: run.ownerId,
      executionId: run.executionId,
      leaseExpiresAt: run.leaseExpiresAt,
      cancellationPolicy: run.cancellationPolicy != null
          ? WorkflowCancellationPolicy.fromJson(
              _decodeMap(run.cancellationPolicy),
            )
          : null,
      cancellationData: run.cancellationData == null
          ? null
          : _decodeMap(run.cancellationData),
    );
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final ctx = _connections.context;
    final step = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('name', stepName)
        .whereEquals('namespace', namespace)
        .first();

    if (step == null) return null;
    return _decodeValue(step.value) as T?;
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      await _saveStepInTransaction(ctx, runId, stepName, value);

      // Update run's updatedAt
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        await ctx.repository<StemWorkflowRun>().update(
          StemWorkflowRunUpdateDto(updatedAt: now),
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  Future<void> _saveStepInTransaction(
    QueryContext ctx,
    String runId,
    String stepName,
    Object? value,
  ) async {
    final encoded = jsonEncode(value);
    final existing = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('name', stepName)
        .whereEquals('namespace', namespace)
        .first();

    if (existing != null) {
      await ctx.repository<StemWorkflowStep>().update(
        StemWorkflowStepUpdateDto(value: encoded),
        where: StemWorkflowStepPartial(
          runId: runId,
          name: stepName,
          namespace: namespace,
        ),
      );
    } else {
      await ctx.repository<StemWorkflowStep>().insert(
        StemWorkflowStepInsertDto(
          runId: runId,
          name: stepName,
          namespace: namespace,
          value: encoded,
        ),
      );
    }
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    final now = _clock.now().toUtc();
    final metadata = _prepareSuspensionData(data, resumeAt: when);

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          resumeAt: when,
          suspensionData: jsonEncode(metadata),
          updatedAt: now,
        ).toMap();
        updates['wait_topic'] = null;
        await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', runId)
            .whereEquals('namespace', namespace)
            .whereIn('status', [
              WorkflowStatus.running.name,
              WorkflowStatus.suspended.name,
            ])
            .update(updates);
      }
    });
  }

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final now = _clock.now().toUtc();
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          waitTopic: topic,
          resumeAt: deadline,
          suspensionData: jsonEncode(metadata),
          updatedAt: now,
        ).toMap();
        updates['resume_at'] = deadline;
        await _updateActiveRun(ctx, runId, updates);
      }
    });
  }

  @override
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      // This conditional update takes the run lock before any watcher write,
      // matching resolution and terminal failure's run-then-watcher order.
      final changed = await _updateActiveRun(ctx, runId, {
        'status': WorkflowStatus.suspended.name,
        'wait_topic': topic,
        'resume_at': deadline,
        'suspension_data': jsonEncode(metadata),
        'updated_at': now,
      });
      if (changed == 0) return;

      final existing = await ctx
          .query<$StemWorkflowWatcher>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .first();

      final watcher = $StemWorkflowWatcher(
        runId: runId,
        stepName: stepName,
        topic: topic,
        namespace: namespace,
        data: jsonEncode(metadata),
        deadline: deadline,
        createdAt: now,
      );

      if (existing != null) {
        await ctx.repository<$StemWorkflowWatcher>().update(watcher);
      } else {
        await ctx.repository<$StemWorkflowWatcher>().insert(watcher);
      }
    });
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.running.name,
          updatedAt: now,
        ).toMap();
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
        final changed = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', runId)
            .whereEquals('namespace', namespace)
            .whereIn('status', [
              WorkflowStatus.running.name,
              WorkflowStatus.suspended.name,
            ])
            .update(updates);
        if (changed > 0) await _deleteWatcher(ctx, runId);
      }
    });
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    await completeIfActive(runId, result);
  }

  @override
  Future<bool> completeIfActive(String runId, Object? result) async =>
      _terminalUpdate(runId, WorkflowStatus.completed, result: result);

  @override
  Future<bool> cancelIfActive(String runId, {String? reason}) async =>
      _terminalUpdate(runId, WorkflowStatus.cancelled, reason: reason);

  Future<bool> _terminalUpdate(
    String runId,
    WorkflowStatus status, {
    Object? result,
    String? reason,
  }) async {
    final now = _clock.now().toUtc();
    return _connections.runInTransaction((ctx) async {
      final changed = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereIn('status', [
            WorkflowStatus.running.name,
            WorkflowStatus.suspended.name,
          ])
          .update({
            'status': status.name,
            if (status == WorkflowStatus.completed)
              'result': jsonEncode(result),
            if (status == WorkflowStatus.cancelled)
              'cancellationData': jsonEncode({
                'reason': reason ?? 'cancelled',
                'cancelledAt': now.toIso8601String(),
              }),
            'suspension_data': null,
            'wait_topic': null,
            'resume_at': null,
            if (status == WorkflowStatus.cancelled) 'execution_id': null,
            'owner_id': null,
            'lease_expires_at': null,
            'updatedAt': now,
          });
      if (changed > 0) await _deleteWatcher(ctx, runId);
      return changed > 0;
    });
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: terminal ? WorkflowStatus.failed.name : null,
          lastError: jsonEncode({
            'error': error.toString(),
            'stack': stack.toString(),
          }),
          updatedAt: now,
        ).toMap();
        if (terminal) {
          updates['owner_id'] = null;
          updates['lease_expires_at'] = null;
          updates['wait_topic'] = null;
          updates['resume_at'] = null;
          updates['suspension_data'] = null;
        }
        final changed = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', runId)
            .whereEquals('namespace', namespace)
            .whereIn('status', [
              WorkflowStatus.running.name,
              WorkflowStatus.suspended.name,
            ])
            .update(updates);
        if (terminal && changed > 0) await _deleteWatcher(ctx, runId);
      }
    });
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.running.name,
          updatedAt: now,
        ).toMap();
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
        updates['suspension_data'] = data != null ? jsonEncode(data) : null;
        updates['execution_id'] = null;
        updates['owner_id'] = null;
        updates['lease_expires_at'] = null;
        final changed = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', runId)
            .whereEquals('namespace', namespace)
            .whereIn('status', [
              WorkflowStatus.running.name,
              WorkflowStatus.suspended.name,
            ])
            .update(updates);
        if (changed > 0) await _deleteWatcher(ctx, runId);
      }
    });
  }

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final leaseExpiresAt = now.add(leaseDuration);
    final updated = await _connections.runInTransaction((ctx) async {
      final query = ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('status', WorkflowStatus.running.name)
          .whereNull('waitTopic')
          .where((PredicateBuilder<StemWorkflowRun> q) {
            q
              ..whereNull('leaseExpiresAt')
              ..orWhere(
                'leaseExpiresAt',
                now,
                PredicateOperator.lessThanOrEqual,
              );
          });
      return query.update({
        'ownerId': ownerId,
        'executionId': null,
        'leaseExpiresAt': leaseExpiresAt,
        'updatedAt': now,
      });
    });
    return updated > 0;
  }

  @override
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final leaseExpiresAt = now.add(leaseDuration);
    final updated = await _connections.runInTransaction((ctx) async {
      final query = ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('status', WorkflowStatus.running.name)
          .whereNull('executionId')
          .whereEquals('ownerId', ownerId);
      return query.update({
        'leaseExpiresAt': leaseExpiresAt,
        'updatedAt': now,
      });
    });
    return updated > 0;
  }

  @override
  Future<void> releaseRun(String runId, {required String ownerId}) async {
    final now = _clock.now().toUtc();
    await _connections.runInTransaction((ctx) async {
      await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereNull('executionId')
          .whereEquals('ownerId', ownerId)
          .update({
            'ownerId': null,
            'leaseExpiresAt': null,
            'updatedAt': now,
          });
    });
  }

  @override
  Future<WorkflowExecutionClaim?> claimRunExecution(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final leaseExpiresAt = now.add(leaseDuration);
    final executionId = _uuid.v7();
    final updated = await _connections.runInTransaction((ctx) {
      return ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('status', WorkflowStatus.running.name)
          .whereNull('waitTopic')
          .where((PredicateBuilder<StemWorkflowRun> q) {
            q
              ..whereNull('leaseExpiresAt')
              ..orWhere(
                'leaseExpiresAt',
                now,
                PredicateOperator.lessThanOrEqual,
              );
          })
          .update({
            'ownerId': ownerId,
            'executionId': executionId,
            'leaseExpiresAt': leaseExpiresAt,
            'updatedAt': now,
          });
    });
    if (updated == 0) return null;
    return WorkflowExecutionClaim(
      runId: runId,
      executionId: executionId,
      ownerId: ownerId,
      leaseExpiresAt: leaseExpiresAt,
    );
  }

  @override
  Future<bool> renewRunExecution(
    String runId, {
    required String executionId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final updated = await _connections.runInTransaction((ctx) {
      return ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('status', WorkflowStatus.running.name)
          .whereEquals('executionId', executionId)
          .whereNotNull('leaseExpiresAt')
          .where('leaseExpiresAt', now, PredicateOperator.greaterThan)
          .update({
            'leaseExpiresAt': now.add(leaseDuration),
            'updatedAt': now,
          });
    });
    return updated > 0;
  }

  @override
  Future<void> releaseRunExecution(
    String runId, {
    required String executionId,
  }) async {
    final now = _clock.now().toUtc();
    await _connections.runInTransaction((ctx) async {
      await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('executionId', executionId)
          .update({
            'ownerId': null,
            'leaseExpiresAt': null,
            'updatedAt': now,
          });
    });
  }

  @override
  Future<TerminalFailureResult> markFailedForExecution(
    String runId, {
    required String executionId,
    required Object error,
    required StackTrace stack,
    bool terminal = true,
  }) async {
    final now = _clock.now().toUtc();
    return _connections.runInTransaction((ctx) async {
      // Serialize the eligibility check, write, and outcome classification
      // with concurrent run mutations. Keep the entire decision inside the
      // transaction that owns this row lock.
      final current = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .lock('FOR UPDATE')
          .first();
      if (current == null ||
          current.executionId != executionId ||
          ![
            WorkflowStatus.running.name,
            WorkflowStatus.suspended.name,
          ].contains(current.status)) {
        if (current?.executionId == executionId &&
            current?.status == WorkflowStatus.failed.name) {
          return TerminalFailureResult.alreadyFailedForExecution;
        }
        return TerminalFailureResult.superseded;
      }

      final changed = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('executionId', executionId)
          .whereIn('status', [
            WorkflowStatus.running.name,
            WorkflowStatus.suspended.name,
          ])
          .update({
            if (terminal) 'status': WorkflowStatus.failed.name,
            'lastError': jsonEncode({
              'error': error.toString(),
              'stack': stack.toString(),
            }),
            if (terminal) 'ownerId': null,
            if (terminal) 'leaseExpiresAt': null,
            if (terminal) 'resumeAt': null,
            if (terminal) 'waitTopic': null,
            'updatedAt': now,
          });
      if (changed > 0 && terminal) await _deleteWatcher(ctx, runId);
      if (changed > 0) return TerminalFailureResult.applied;

      return TerminalFailureResult.superseded;
    });
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    return _connections.runInTransaction((ctx) async {
      // SELECT runs where resume_at has passed
      final dueRuns = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('namespace', namespace)
          .whereNotNull('resumeAt')
          .where('resumeAt', now, PredicateOperator.lessThanOrEqual)
          .whereEquals('status', WorkflowStatus.suspended.name)
          .limit(limit)
          .get();

      if (dueRuns.isEmpty) {
        return const <String>[];
      }

      // Update all to clear resume_at
      final nowUtc = now.toUtc();
      for (final run in dueRuns) {
        await ctx.repository<StemWorkflowRun>().update({
          'resume_at': null,
          'updated_at': nowUtc,
        }, where: StemWorkflowRunPartial(id: run.id, namespace: namespace));
      }

      return dueRuns.map((r) => r.id).toList(growable: false);
    });
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final ctx = _connections.context;
    // Check watchers first
    final watcherRows = await ctx
        .query<$StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    if (watcherRows.isNotEmpty) {
      return watcherRows.map((row) => row.runId).toList(growable: false);
    }

    // Fallback to runs with wait_topic
    final fallbackRows = await ctx
        .query<StemWorkflowRun>()
        .whereEquals('waitTopic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    return fallbackRows.map((r) => r.id).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    return _connections.runInTransaction((ctx) async {
      final watchers = await ctx
          .query<$StemWorkflowWatcher>()
          .whereEquals('topic', topic)
          .whereEquals('namespace', namespace)
          .orderBy('runId')
          .limit(limit)
          .get();

      if (watchers.isEmpty) {
        return const <WorkflowWatcherResolution>[];
      }

      final resolutions = <WorkflowWatcherResolution>[];
      final now = _clock.now();
      final nowUtc = now.toUtc();

      for (final candidate in watchers) {
        // The initial watcher query is only a candidate scan. Lock and
        // re-read the run first, then the exact watcher row. This prevents a
        // resolver from reviving a run after markFailedForExecution has
        // terminally failed it, and also observes a replacement watcher for
        // the same run/topic.
        final run = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', candidate.runId)
            .whereEquals('namespace', namespace)
            .lock('FOR UPDATE')
            .first();
        if (run == null ||
            run.status != WorkflowStatus.suspended.name ||
            run.waitTopic != topic) {
          continue;
        }

        final watcher = await ctx
            .query<$StemWorkflowWatcher>()
            .whereEquals('runId', candidate.runId)
            .whereEquals('namespace', namespace)
            .whereEquals('topic', topic)
            .lock('FOR UPDATE')
            .first();
        if (watcher == null) continue;

        // Build metadata for resumption
        final data = _decodeMap(watcher.data);
        final metadata = Map<String, Object?>.from(data);
        metadata['type'] = 'event';
        metadata['topic'] = topic;
        metadata['payload'] = payload;
        metadata
          ..putIfAbsent('step', () => watcher.stepName)
          ..putIfAbsent(
            'iterationStep',
            () => metadata['step'] ?? watcher.stepName,
          );
        metadata['deliveredAt'] = now.toIso8601String();

        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.running.name,
          suspensionData: jsonEncode(metadata),
          updatedAt: nowUtc,
        ).toMap();
        updates['wait_topic'] = null;
        updates['resume_at'] = null;
        final changed = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', watcher.runId)
            .whereEquals('namespace', namespace)
            .whereEquals('status', WorkflowStatus.suspended.name)
            .whereEquals('waitTopic', topic)
            .update(updates);
        if (changed == 0) continue;

        // Delete the watcher (resolved)
        await ctx.repository<$StemWorkflowWatcher>().delete(watcher);

        resolutions.add(
          WorkflowWatcherResolution(
            runId: watcher.runId,
            stepName: watcher.stepName,
            topic: topic,
            resumeData: metadata,
          ),
        );
      }

      return resolutions;
    });
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final ctx = _connections.context;
    final rows = await ctx
        .query<$StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    if (rows.isEmpty) {
      return const [];
    }

    return rows
        .map(
          (row) => WorkflowWatcher(
            runId: row.runId,
            stepName: row.stepName,
            topic: row.topic,
            createdAt: row.createdAt,
            deadline: row.deadline,
            data: _decodeMap(row.data),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    await cancelIfActive(runId, reason: reason);
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final stepRows = await ctx
          .query<StemWorkflowStep>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .orderBy('name')
          .get();

      // Calculate which steps to keep
      final names = stepRows.map((row) => row.name).toList();
      final baseIndexMap = <String, int>{};
      var nextIndex = 0;
      final entryIndexes = <int>[];

      for (final name in names) {
        final base = _baseStepName(name);
        baseIndexMap.putIfAbsent(base, () => nextIndex++);
        entryIndexes.add(baseIndexMap[base]!);
      }

      final targetIndex = baseIndexMap[stepName];
      if (targetIndex == null) return;

      final keep = <StemWorkflowStepInsertDto>[];
      for (var i = 0; i < stepRows.length; i++) {
        final baseIndex = entryIndexes[i];
        if (baseIndex < targetIndex) {
          final step = stepRows[i];
          keep.add(
            StemWorkflowStepInsertDto(
              runId: runId,
              name: step.name,
              namespace: namespace,
              value: step.value,
            ),
          );
        } else {
          break;
        }
      }

      await ctx
          .query<StemWorkflowStep>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .delete();

      if (keep.isNotEmpty) {
        await ctx.repository<StemWorkflowStep>().insertMany(keep);
      }

      final keptNames = keep.map((step) => step.name).toSet();
      final journalRows = await ctx.driver.queryRaw(
        '''
SELECT DISTINCT name
FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ?
''',
        [namespace, runId],
      );
      for (final row in journalRows) {
        final name = row['name']! as String;
        if (!keptNames.contains(name)) {
          await ctx.driver.executeRaw(
            '''
DELETE FROM stem_workflow_journal
WHERE namespace = ? AND run_id = ? AND name = ?
''',
            [namespace, runId, name],
          );
        }
      }

      // Update run status
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          suspensionData: jsonEncode({
            'step': stepName,
            'iteration': 0,
            'iterationStep': stepName,
          }),
          updatedAt: _clock.now().toUtc(),
        ).toMap();
        updates['execution_id'] = null;
        updates['owner_id'] = null;
        updates['lease_expires_at'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final ctx = _connections.context;
    var query = ctx.query<StemWorkflowRun>();
    query = query.whereEquals('namespace', namespace);

    if (workflow != null) {
      query = query.whereEquals('workflow', workflow);
    }

    if (status != null) {
      query = query.whereEquals('status', status.name);
    }

    final ids = await query
        .orderBy('updatedAt', descending: true)
        .orderBy('id', descending: true)
        .offset(offset)
        .limit(limit)
        .get()
        .then((runs) => runs.map((r) => r.id).toList());

    final results = <RunState>[];
    for (final id in ids) {
      final state = await _readRunState(ctx, id);
      if (state != null) {
        results.add(state);
      }
    }

    return results;
  }

  @override
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async {
    final resolvedNow = (now ?? _clock.now()).toUtc();
    final ctx = _connections.context;
    final runs = await ctx
        .query<StemWorkflowRun>()
        .whereEquals('namespace', namespace)
        .whereEquals('status', WorkflowStatus.running.name)
        .whereNull('waitTopic')
        .where((PredicateBuilder<StemWorkflowRun> q) {
          q
            ..whereNull('leaseExpiresAt')
            ..orWhere(
              'leaseExpiresAt',
              resolvedNow,
              PredicateOperator.lessThanOrEqual,
            );
        })
        .orderBy('updatedAt', descending: true)
        .offset(offset)
        .limit(limit)
        .get();
    return runs.map((run) => run.id).toList(growable: false);
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    final ctx = _connections.context;
    final rows = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .orderBy('name')
        .get();

    final entries = <WorkflowStepEntry>[];
    var position = 0;

    for (final row in rows) {
      entries.add(
        WorkflowStepEntry(
          name: row.name,
          value: _decodeValue(row.value),
          position: position,
        ),
      );
      position += 1;
    }

    return entries;
  }

  Future<int> _updateActiveRun(
    QueryContext ctx,
    String runId,
    Map<String, Object?> updates,
  ) => ctx
      .query<StemWorkflowRun>()
      .whereEquals('id', runId)
      .whereEquals('namespace', namespace)
      .whereIn('status', [
        WorkflowStatus.running.name,
        WorkflowStatus.suspended.name,
      ])
      .update(updates);

  Future<void> _deleteWatcher(QueryContext ctx, String runId) async {
    // Legacy lifecycle methods call this before updating the run. Acquire
    // the run lock first here too, so they cannot invert the resolver's
    // run-then-watcher lock order.
    await ctx
        .query<StemWorkflowRun>()
        .whereEquals('id', runId)
        .whereEquals('namespace', namespace)
        .lock('FOR UPDATE')
        .first();
    final watcher = await ctx
        .query<$StemWorkflowWatcher>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (watcher != null) {
      await ctx.repository<$StemWorkflowWatcher>().delete(watcher);
    }
  }

  WorkflowJournalEntry _journalEntry(
    Map<String, dynamic> row,
    String runId,
    WorkflowJournalKind kind,
    String name,
  ) {
    final decoded = _decodeValue(row['data']);
    return WorkflowJournalEntry(
      runId: runId,
      kind: kind,
      name: name,
      revision: _asInt(row['revision']),
      position: row['position'] == null ? null : _asInt(row['position']),
      data: decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.parse(value.toString());

  Map<String, Object?> _decodeMap(dynamic input) {
    if (input == null) return const {};
    if (input is String) {
      try {
        final decoded = jsonDecode(input);
        return decoded is Map
            ? decoded.map((key, value) => MapEntry(key as String, value))
            : const {};
      } on Object {
        return const {};
      }
    }
    if (input is Map) {
      return input.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  Object? _decodeValue(dynamic input) {
    if (input == null) return null;
    if (input is String) {
      try {
        return jsonDecode(input);
      } on Object {
        return input;
      }
    }
    return input;
  }

  String _baseStepName(String name) {
    final index = name.indexOf('#');
    if (index == -1) return name;
    return name.substring(0, index);
  }
}
