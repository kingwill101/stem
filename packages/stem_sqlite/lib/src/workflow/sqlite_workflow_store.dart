import 'dart:convert';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/connection.dart';
import 'package:stem_sqlite/src/models/models.dart';
import 'package:uuid/uuid.dart';

/// SQLite-backed implementation of [WorkflowStore].
class SqliteWorkflowStore
    implements
        WorkflowStore,
        WorkflowTerminalStore,
        FencedWorkflowStore,
        WorkflowJournalStore {
  SqliteWorkflowStore._(
    this._connections,
    this._clock, {
    required this.namespace,
  }) : _context = _connections.context;

  /// Creates a workflow store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<SqliteWorkflowStore> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    WorkflowClock clock = const SystemWorkflowClock(),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.openWithDataSource(dataSource);
    return SqliteWorkflowStore._(
      connections,
      clock,
      namespace: resolvedNamespace,
    );
  }

  /// Opens a SQLite-backed workflow store using [file].
  static Future<SqliteWorkflowStore> open(
    File file, {
    String namespace = 'stem',
    WorkflowClock clock = const SystemWorkflowClock(),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.open(file);
    return SqliteWorkflowStore._(
      connections,
      clock,
      namespace: resolvedNamespace,
    );
  }

  final SqliteConnections _connections;
  final QueryContext _context;
  final WorkflowClock _clock;

  /// Namespace used to scope workflow data.
  final String namespace;
  final Uuid _uuid = const Uuid();

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

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? runId,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final now = _clock.now().toUtc();
    final id = (runId != null && runId.trim().isNotEmpty)
        ? runId.trim()
        : 'wf-${_uuid.v7()}';
    final policyJson = cancellationPolicy == null || cancellationPolicy.isEmpty
        ? null
        : jsonEncode(cancellationPolicy.toJson());

    await _connections.runInTransaction((ctx) async {
      await ctx.repository<StemWorkflowRun>().insert(
        StemWorkflowRunInsertDto(
          id: id,
          namespace: namespace,
          workflow: workflow,
          status: WorkflowStatus.running.name,
          params: jsonEncode(params),
          cancellationPolicy: policyJson,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    return _readRunState(_context, runId);
  }

  Future<RunState?> _readRunState(QueryContext ctx, String runId) async {
    final run = await ctx
        .query<StemWorkflowRun>()
        .whereEquals('id', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (run == null) return null;

    final steps = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .get();

    final baseSteps = <String>{};
    for (final step in steps) {
      baseSteps.add(_baseStepName(step.name));
    }

    final cancellationPolicyRaw = _decodeMap(run.cancellationPolicy);
    final cancellationData = _decodeMap(run.cancellationData);

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
      cancellationPolicy: cancellationPolicyRaw.isNotEmpty
          ? WorkflowCancellationPolicy.fromJson(cancellationPolicyRaw)
          : null,
      cancellationData: cancellationData.isEmpty ? null : cancellationData,
    );
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final step = await _context
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

      await ctx.repository<StemWorkflowRun>().update(
        StemWorkflowRunUpdateDto(updatedAt: now),
        where: StemWorkflowRunPartial(id: runId, namespace: namespace),
      );
    });
  }

  @override
  Future<WorkflowJournalSnapshot?> readJournal(
    String runId,
    WorkflowJournalKind kind,
    String name,
  ) async {
    return _connections.runInTransaction((ctx) async {
      final run = await _readRunState(ctx, runId);
      if (run == null) {
        return null;
      }
      final rows = await ctx.driver.queryRaw(
        'SELECT * FROM wf_journal WHERE namespace = ? AND run_id = ? '
        'AND kind = ? AND name = ?',
        [namespace, runId, kind.name, name],
      );
      return WorkflowJournalSnapshot(
        run: run,
        entry: rows.isEmpty ? null : _journalEntry(rows.single),
      );
    });
  }

  @override
  Future<List<WorkflowJournalEntry>> listCompensations(String runId) async {
    final rows = await _context.driver.queryRaw(
      'SELECT * FROM wf_journal WHERE namespace = ? AND run_id = ? '
      'AND kind = ? ORDER BY position DESC',
      [namespace, runId, WorkflowJournalKind.compensation.name],
    );
    return rows.map(_journalEntry).toList(growable: false);
  }

  WorkflowJournalEntry _journalEntry(Map<String, Object?> row) {
    return WorkflowJournalEntry(
      runId: row['run_id']! as String,
      kind: WorkflowJournalKind.values.byName(row['kind']! as String),
      name: row['name']! as String,
      revision: (row['revision']! as num).toInt(),
      data: _decodeMap(row['data']! as String),
      position: (row['position'] as num?)?.toInt(),
    );
  }

  @override
  Future<bool> commitJournal(
    WorkflowJournalEntry entry, {
    required int expectedRevision,
    required String executionId,
    WorkflowJournalCheckpoint? checkpoint,
  }) async {
    if (entry.revision != expectedRevision + 1) return false;
    return _connections.runInTransaction((ctx) async {
      final status = entry.kind == WorkflowJournalKind.step
          ? WorkflowStatus.running.name
          : WorkflowStatus.failed.name;
      await ctx.driver.executeRaw(
        'UPDATE wf_runs SET updated_at = updated_at WHERE id = ? '
        'AND namespace = ? AND execution_id = ? AND status = ?',
        [entry.runId, namespace, executionId, status],
      );
      final fenced = await ctx.driver.queryRaw('SELECT changes() AS changed');
      if (fenced.isEmpty || (fenced.single['changed']! as num) == 0) {
        return false;
      }
      final rows = await ctx.driver.queryRaw(
        'SELECT revision, position FROM wf_journal WHERE namespace = ? '
        'AND run_id = ? AND kind = ? AND name = ?',
        [namespace, entry.runId, entry.kind.name, entry.name],
      );
      final old = rows.isEmpty ? null : rows.single;
      final revision = old == null ? 0 : (old['revision']! as num).toInt();
      if (revision != expectedRevision ||
          (entry.kind == WorkflowJournalKind.compensation && old == null)) {
        return false;
      }
      final encoded = jsonEncode(entry.data);
      if (old == null) {
        await ctx.driver.executeRaw(
          'INSERT INTO wf_journal '
          '(namespace, run_id, kind, name, revision, data, position) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            namespace,
            entry.runId,
            entry.kind.name,
            entry.name,
            entry.revision,
            encoded,
            entry.position,
          ],
        );
      } else {
        await ctx.driver.executeRaw(
          'UPDATE wf_journal SET revision = ?, data = ? '
          'WHERE namespace = ? AND run_id = ? AND kind = ? AND name = ? '
          'AND revision = ?',
          [
            entry.revision,
            encoded,
            namespace,
            entry.runId,
            entry.kind.name,
            entry.name,
            expectedRevision,
          ],
        );
        final changed = await ctx.driver.queryRaw(
          'SELECT changes() AS changed',
        );
        if (changed.isEmpty || (changed.single['changed']! as num) == 0) {
          return false;
        }
      }
      if (checkpoint != null && entry.kind == WorkflowJournalKind.step) {
        await _saveStepInTransaction(
          ctx,
          entry.runId,
          entry.name,
          checkpoint.value,
        );
        final registration = checkpoint.compensation;
        if (registration != null) {
          final max = await ctx.driver.queryRaw(
            'SELECT COALESCE(MAX(position), 0) + 1 AS next_position '
            'FROM wf_journal WHERE namespace = ? AND run_id = ? AND kind = ?',
            [namespace, entry.runId, WorkflowJournalKind.compensation.name],
          );
          await ctx.driver.executeRaw(
            'INSERT INTO wf_journal '
            '(namespace, run_id, kind, name, revision, data, position) '
            'VALUES (?, ?, ?, ?, 1, ?, ?) ON CONFLICT DO NOTHING',
            [
              namespace,
              entry.runId,
              WorkflowJournalKind.compensation.name,
              entry.name,
              jsonEncode(registration.toJournalData()),
              (max.single['next_position']! as num).toInt(),
            ],
          );
        }
      }
      return true;
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
        await _updateActiveRun(ctx, runId, updates);
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
    final now = _clock.now().toUtc();
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    final payload = jsonEncode(metadata);

    await _connections.runInTransaction((ctx) async {
      final changed = await _updateActiveRun(ctx, runId, {
        'status': WorkflowStatus.suspended.name,
        'wait_topic': topic,
        'resume_at': deadline,
        'suspension_data': payload,
        'updated_at': now,
      });
      if (changed == 0) return;

      final existing = await ctx
          .query<StemWorkflowWatcher>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (existing != null) {
        await ctx.repository<StemWorkflowWatcher>().update(
          StemWorkflowWatcherUpdateDto(
            stepName: stepName,
            topic: topic,
            data: payload,
            createdAt: now,
            deadline: deadline,
          ),
          where: StemWorkflowWatcherPartial(
            runId: runId,
            namespace: namespace,
          ),
        );
      } else {
        await ctx.repository<StemWorkflowWatcher>().insert(
          StemWorkflowWatcherInsertDto(
            runId: runId,
            stepName: stepName,
            topic: topic,
            namespace: namespace,
            data: payload,
            createdAt: now,
            deadline: deadline,
          ),
        );
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
  Future<bool> completeIfActive(String runId, Object? result) async {
    final now = _clock.now().toUtc();

    return _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.completed.name,
          result: result != null ? jsonEncode(result) : null,
          updatedAt: now,
        ).toMap();
        if (result == null) {
          updates['result'] = null;
        }
        updates['suspension_data'] = null;
        updates['wait_topic'] = null;
        updates['resume_at'] = null;
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
        return changed > 0;
      }
      return false;
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
          suspensionData: data != null ? jsonEncode(data) : null,
          updatedAt: now,
        ).toMap();
        updates['execution_id'] = null;
        updates['owner_id'] = null;
        updates['lease_expires_at'] = null;
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
        if (data == null) {
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
  Future<WorkflowExecutionClaim?> claimRunExecution(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final expiresAt = now.add(leaseDuration);
    final executionId = _uuid.v4();
    return _connections.runInTransaction((ctx) async {
      final updated = await ctx
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
            'leaseExpiresAt': expiresAt,
            'updatedAt': now,
          });
      if (updated == 0) return null;
      return WorkflowExecutionClaim(
        runId: runId,
        executionId: executionId,
        ownerId: ownerId,
        leaseExpiresAt: expiresAt,
      );
    });
  }

  @override
  Future<bool> renewRunExecution(
    String runId, {
    required String executionId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now().toUtc();
    final expiresAt = now.add(leaseDuration);
    return _connections.runInTransaction((ctx) async {
      final updated = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('status', WorkflowStatus.running.name)
          .whereEquals('executionId', executionId)
          .whereNotNull('ownerId')
          .where('leaseExpiresAt', now, PredicateOperator.greaterThan)
          .update({'leaseExpiresAt': expiresAt, 'updatedAt': now});
      return updated > 0;
    });
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
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();
      if (run == null || run.executionId != executionId) {
        return TerminalFailureResult.superseded;
      }
      if (run.status == WorkflowStatus.failed.name) {
        return TerminalFailureResult.alreadyFailedForExecution;
      }
      if (run.status == WorkflowStatus.completed.name ||
          run.status == WorkflowStatus.cancelled.name) {
        return TerminalFailureResult.superseded;
      }
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
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
      }
      final changed = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereEquals('executionId', executionId)
          .whereEquals('status', run.status)
          .update(updates);
      if (changed > 0 && terminal) await _deleteWatcher(ctx, runId);
      return changed > 0
          ? TerminalFailureResult.applied
          : TerminalFailureResult.superseded;
    });
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
          .whereEquals('ownerId', ownerId)
          .whereNull('executionId');
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
          .whereEquals('ownerId', ownerId)
          .whereNull('executionId')
          .update({
            'ownerId': null,
            'leaseExpiresAt': null,
            'updatedAt': now,
          });
    });
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    return _connections.runInTransaction((ctx) async {
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

      final nowUtc = now.toUtc();
      for (final run in dueRuns) {
        final updates = StemWorkflowRunUpdateDto(updatedAt: nowUtc).toMap();
        updates['resume_at'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: run.id, namespace: namespace),
        );
      }

      return dueRuns.map((run) => run.id).toList(growable: false);
    });
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final watcherRows = await _context
        .query<StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .orderBy('createdAt')
        .limit(limit)
        .get();

    if (watcherRows.isNotEmpty) {
      return watcherRows.map((row) => row.runId).toList(growable: false);
    }

    final fallbackRows = await _context
        .query<StemWorkflowRun>()
        .whereEquals('waitTopic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    return fallbackRows.map((row) => row.id).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    return _connections.runInTransaction((ctx) async {
      final watchers = await ctx
          .query<StemWorkflowWatcher>()
          .whereEquals('topic', topic)
          .whereEquals('namespace', namespace)
          .orderBy('createdAt')
          .limit(limit)
          .get();

      if (watchers.isEmpty) {
        return const <WorkflowWatcherResolution>[];
      }

      final resolutions = <WorkflowWatcherResolution>[];
      final now = _clock.now();
      final nowUtc = now.toUtc();

      for (final watcher in watchers) {
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

        final run = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', watcher.runId)
            .whereEquals('namespace', namespace)
            .whereIn('status', [
              WorkflowStatus.running.name,
              WorkflowStatus.suspended.name,
            ])
            .first();

        if (run != null) {
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
              .whereIn('status', [
                WorkflowStatus.running.name,
                WorkflowStatus.suspended.name,
              ])
              .update(updates);
          if (changed > 0) {
            await ctx.repository<StemWorkflowWatcher>().delete(watcher);
            resolutions.add(
              WorkflowWatcherResolution(
                runId: watcher.runId,
                stepName: watcher.stepName,
                topic: topic,
                resumeData: metadata,
              ),
            );
          }
        }
      }

      return resolutions;
    });
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final rows = await _context
        .query<StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .orderBy('createdAt')
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
            topic: topic,
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
  Future<bool> cancelIfActive(String runId, {String? reason}) async {
    final now = _clock.now();
    final nowUtc = now.toUtc();
    final cancellation = jsonEncode({
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    });

    return _connections.runInTransaction((ctx) async {
      final changed = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .whereIn('status', [
            WorkflowStatus.running.name,
            WorkflowStatus.suspended.name,
          ])
          .update(
            (() {
              final updates = StemWorkflowRunUpdateDto(
                status: WorkflowStatus.cancelled.name,
                cancellationData: cancellation,
                updatedAt: nowUtc,
              ).toMap();
              updates['suspension_data'] = null;
              updates['wait_topic'] = null;
              updates['resume_at'] = null;
              updates['owner_id'] = null;
              updates['lease_expires_at'] = null;
              return updates;
            })(),
          );
      if (changed > 0) await _deleteWatcher(ctx, runId);
      return changed > 0;
    });
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

      // Rewind is administrative: discard journal state belonging to removed
      // checkpoint names, while retaining all earlier checkpoint records.
      final keepNames = keep.map((step) => step.name).toList();
      if (keepNames.isEmpty) {
        await ctx.driver.executeRaw(
          'DELETE FROM wf_journal WHERE namespace = ? AND run_id = ?',
          [namespace, runId],
        );
      } else {
        final placeholders = List.filled(keepNames.length, '?').join(', ');
        await ctx.driver.executeRaw(
          'DELETE FROM wf_journal WHERE namespace = ? AND run_id = ? '
          'AND name NOT IN ($placeholders)',
          [namespace, runId, ...keepNames],
        );
      }

      final updates = StemWorkflowRunUpdateDto(
        status: WorkflowStatus.suspended.name,
        suspensionData: jsonEncode({
          'step': stepName,
          'iteration': 0,
          'iterationStep': stepName,
        }),
        updatedAt: _clock.now().toUtc(),
      ).toMap();
      updates['wait_topic'] = null;
      updates['resume_at'] = null;
      updates['owner_id'] = null;
      updates['lease_expires_at'] = null;
      updates['execution_id'] = null;
      await ctx.repository<StemWorkflowRun>().update(
        updates,
        where: StemWorkflowRunPartial(id: runId, namespace: namespace),
      );
    });
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _context.query<StemWorkflowRun>();
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
        .then((runs) => runs.map((run) => run.id).toList());

    final results = <RunState>[];
    for (final id in ids) {
      final state = await _readRunState(_context, id);
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
    final runs = await _context
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
    final rows = await _context
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

  /// Closes the workflow store and releases database resources.
  Future<void> close() => _connections.close();

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
    final watcher = await ctx
        .query<StemWorkflowWatcher>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (watcher != null) {
      await ctx.repository<StemWorkflowWatcher>().delete(watcher);
    }
  }

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
