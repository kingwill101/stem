import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:stem/stem.dart';

void _ensureColumn(
  Database db,
  String table,
  String column,
  String definition,
) {
  final existing = db.select('PRAGMA table_info($table)');
  final hasColumn = existing.any((row) => row['name'] == column);
  if (!hasColumn) {
    db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

class SqliteWorkflowStore implements WorkflowStore {
  SqliteWorkflowStore._(this._db, this._clock);

  final Database _db;
  final WorkflowClock _clock;
  int _idCounter = 0;

  factory SqliteWorkflowStore.open(
    File file, {
    WorkflowClock clock = const SystemWorkflowClock(),
  }) {
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS wf_runs (
        id TEXT PRIMARY KEY,
        workflow TEXT NOT NULL,
        status TEXT NOT NULL,
        params TEXT NOT NULL,
        result TEXT,
        wait_topic TEXT,
        resume_at INTEGER,
        last_error TEXT,
        suspension_data TEXT,
        cancellation_policy TEXT,
        cancellation_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (CAST(1000 * strftime('%s','now') AS INTEGER)),
        updated_at INTEGER NOT NULL DEFAULT (CAST(1000 * strftime('%s','now') AS INTEGER))
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS wf_steps (
        run_id TEXT NOT NULL,
        name TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (run_id, name)
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS wf_runs_resume_idx ON wf_runs(resume_at)
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS wf_runs_topic_idx ON wf_runs(wait_topic)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS wf_watchers (
        run_id TEXT PRIMARY KEY REFERENCES wf_runs(id) ON DELETE CASCADE,
        step_name TEXT NOT NULL,
        topic TEXT NOT NULL,
        data TEXT,
        created_at INTEGER NOT NULL DEFAULT (CAST(1000 * strftime('%s','now') AS INTEGER)),
        deadline INTEGER
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS wf_watchers_topic_idx ON wf_watchers(topic, created_at)',
    );
    _ensureColumn(db, 'wf_runs', 'cancellation_policy', 'TEXT');
    _ensureColumn(db, 'wf_runs', 'cancellation_data', 'TEXT');
    _ensureColumn(
      db,
      'wf_runs',
      'created_at',
      "INTEGER NOT NULL DEFAULT (CAST(1000 * strftime('%s','now') AS INTEGER))",
    );
    _ensureColumn(
      db,
      'wf_runs',
      'updated_at',
      "INTEGER NOT NULL DEFAULT (CAST(1000 * strftime('%s','now') AS INTEGER))",
    );
    return SqliteWorkflowStore._(db, clock);
  }

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
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final nowInstant = _clock.now();
    final now = nowInstant.millisecondsSinceEpoch;
    final id = 'wf-${nowInstant.microsecondsSinceEpoch}-${_idCounter++}';
    final policyJson = cancellationPolicy == null || cancellationPolicy.isEmpty
        ? null
        : jsonEncode(cancellationPolicy.toJson());
    _db.execute(
      'INSERT INTO wf_runs(id, workflow, status, params, created_at, updated_at, cancellation_policy) '
      'VALUES(?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        workflow,
        WorkflowStatus.running.name,
        jsonEncode(params),
        now,
        now,
        policyJson,
      ],
    );
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    final row = _db.select(
      'SELECT id, workflow, status, params, result, wait_topic, resume_at, '
      'last_error, suspension_data, cancellation_policy, cancellation_data, '
      'created_at, updated_at FROM wf_runs WHERE id = ?',
      [runId],
    ).firstOrNull;
    if (row == null) return null;
    final params = _decodeMap(row['params'] as String?);
    final suspension = _decodeMap(row['suspension_data'] as String?);
    final cursor =
        _db
                .select(
                  '''
          SELECT COUNT(
            DISTINCT CASE instr(name, '#')
              WHEN 0 THEN name
              ELSE substr(name, 1, instr(name, '#') - 1)
            END
          ) AS count
          FROM wf_steps
          WHERE run_id = ?
          ''',
                  [runId],
                )
                .first['count']
            as int;
    final createdAt =
        _decodeDate(row['created_at'] as int?) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final updatedAt = _decodeDate(row['updated_at'] as int?);
    final cancellationPolicy = _decode(row['cancellation_policy'] as String?);
    final cancellationDataRaw = _decodeMap(row['cancellation_data'] as String?);

    return RunState(
      id: row['id'] as String,
      workflow: row['workflow'] as String,
      status: WorkflowStatus.values.firstWhere(
        (v) => v.name == (row['status'] as String),
        orElse: () => WorkflowStatus.running,
      ),
      cursor: cursor,
      params: params,
      result: _decode(row['result'] as String?),
      waitTopic: row['wait_topic'] as String?,
      resumeAt: _decodeDate(row['resume_at'] as int?),
      lastError: _decodeMap(row['last_error'] as String?),
      suspensionData: suspension,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancellationPolicy:
          cancellationPolicy is Map && cancellationPolicy.isNotEmpty
          ? WorkflowCancellationPolicy.fromJson(cancellationPolicy)
          : null,
      cancellationData: cancellationDataRaw.isEmpty
          ? null
          : cancellationDataRaw,
    );
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final row = _db.select(
      'SELECT value FROM wf_steps WHERE run_id = ? AND name = ?',
      [runId, stepName],
    ).firstOrNull;
    if (row == null) return null;
    return _decode(row['value'] as String?) as T?;
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'INSERT OR REPLACE INTO wf_steps(run_id, name, value) VALUES(?, ?, ?)',
        [runId, stepName, jsonEncode(value)],
      );
      _db.execute('UPDATE wf_runs SET updated_at = ? WHERE id = ?', [
        nowMillis,
        runId,
      ]);
      _db.execute('COMMIT');
    } catch (error) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    final metadata = _prepareSuspensionData(data, resumeAt: when);
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = ?, wait_topic = NULL, '
      'suspension_data = ?, updated_at = ? WHERE id = ?',
      [
        WorkflowStatus.suspended.name,
        when.millisecondsSinceEpoch,
        jsonEncode(metadata),
        nowMillis,
        runId,
      ],
    );
  }

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    _db.execute(
      'UPDATE wf_runs SET status = ?, wait_topic = ?, resume_at = ?, '
      'suspension_data = ?, updated_at = ? WHERE id = ?',
      [
        WorkflowStatus.suspended.name,
        topic,
        deadline?.millisecondsSinceEpoch,
        jsonEncode(metadata),
        nowMillis,
        runId,
      ],
    );
  }

  @override
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    final payload = jsonEncode(metadata);
    final deadlineMillis = deadline?.millisecondsSinceEpoch;
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'INSERT INTO wf_watchers(run_id, step_name, topic, data, created_at, deadline) '
        'VALUES(?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(run_id) DO UPDATE SET '
        'step_name = excluded.step_name, '
        'topic = excluded.topic, '
        'data = excluded.data, '
        'created_at = excluded.created_at, '
        'deadline = excluded.deadline',
        [runId, stepName, topic, payload, nowMillis, deadlineMillis],
      );
      _db.execute(
        'UPDATE wf_runs SET status = ?, wait_topic = ?, resume_at = ?, '
        'suspension_data = ?, updated_at = ? WHERE id = ?',
        [
          WorkflowStatus.suspended.name,
          topic,
          deadlineMillis,
          payload,
          nowMillis,
          runId,
        ],
      );
      _db.execute('COMMIT');
    } catch (error) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    _deleteWatcher(runId);
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = NULL, wait_topic = NULL, '
      'updated_at = ? WHERE id = ?',
      [WorkflowStatus.running.name, nowMillis, runId],
    );
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    _deleteWatcher(runId);
    _db.execute(
      'UPDATE wf_runs SET status = ?, result = ?, suspension_data = NULL, '
      'updated_at = ? WHERE id = ?',
      [WorkflowStatus.completed.name, jsonEncode(result), nowMillis, runId],
    );
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    if (terminal) {
      _deleteWatcher(runId);
    }
    _db.execute(
      'UPDATE wf_runs SET status = ?, last_error = ?, updated_at = ? WHERE id = ?',
      [
        (terminal ? WorkflowStatus.failed : WorkflowStatus.running).name,
        jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
        nowMillis,
        runId,
      ],
    );
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final nowMillis = _clock.now().millisecondsSinceEpoch;
    _deleteWatcher(runId);
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = NULL, wait_topic = NULL, '
      'suspension_data = ?, updated_at = ? WHERE id = ?',
      [WorkflowStatus.running.name, jsonEncode(data), nowMillis, runId],
    );
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    final rows = _db.select(
      'SELECT id FROM wf_runs WHERE resume_at IS NOT NULL '
      'AND resume_at <= ? AND status = ? LIMIT ?',
      [now.millisecondsSinceEpoch, WorkflowStatus.suspended.name, limit],
    );
    final ids = rows.map((r) => r['id'] as String).toList(growable: false);
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      _db.execute(
        'UPDATE wf_runs SET resume_at = NULL WHERE id IN ($placeholders)',
        ids,
      );
    }
    return ids;
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final watcherRows = _db.select(
      'SELECT run_id FROM wf_watchers WHERE topic = ? '
      'ORDER BY created_at ASC LIMIT ?',
      [topic, limit],
    );
    if (watcherRows.isNotEmpty) {
      return watcherRows
          .map((row) => row['run_id'] as String)
          .toList(growable: false);
    }
    final fallback = _db.select(
      'SELECT id FROM wf_runs WHERE wait_topic = ? LIMIT ?',
      [topic, limit],
    );
    return fallback.map((r) => r['id'] as String).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    final now = _clock.now();
    final nowMs = now.millisecondsSinceEpoch;
    final nowIso = now.toIso8601String();
    _db.execute('BEGIN IMMEDIATE');
    try {
      final rows = _db.select(
        'SELECT run_id, step_name, data FROM wf_watchers '
        'WHERE topic = ? ORDER BY created_at ASC LIMIT ?',
        [topic, limit],
      );
      if (rows.isEmpty) {
        _db.execute('COMMIT');
        return const [];
      }
      final resolutions = <WorkflowWatcherResolution>[];
      for (final row in rows) {
        final runId = row['run_id'] as String;
        final stepName = row['step_name'] as String;
        final stored = _decodeMap(row['data'] as String?);
        final metadata = Map<String, Object?>.from(stored);
        metadata['type'] = 'event';
        metadata['topic'] = topic;
        metadata['payload'] = payload;
        metadata.putIfAbsent('step', () => stepName);
        metadata.putIfAbsent(
          'iterationStep',
          () => metadata['step'] ?? stepName,
        );
        metadata['deliveredAt'] = nowIso;

        _db.execute(
          'UPDATE wf_runs SET status = ?, wait_topic = NULL, resume_at = NULL, '
          'suspension_data = ?, updated_at = ? WHERE id = ?',
          [WorkflowStatus.running.name, jsonEncode(metadata), nowMs, runId],
        );

        _db.execute('DELETE FROM wf_watchers WHERE run_id = ?', [runId]);

        resolutions.add(
          WorkflowWatcherResolution(
            runId: runId,
            stepName: stepName,
            topic: topic,
            resumeData: metadata,
          ),
        );
      }
      _db.execute('COMMIT');
      return resolutions;
    } catch (error) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final rows = _db.select(
      'SELECT run_id, step_name, data, created_at, deadline '
      'FROM wf_watchers WHERE topic = ? ORDER BY created_at ASC LIMIT ?',
      [topic, limit],
    );
    if (rows.isEmpty) {
      return const [];
    }
    return rows
        .map(
          (row) => WorkflowWatcher(
            runId: row['run_id'] as String,
            stepName: row['step_name'] as String,
            topic: topic,
            createdAt:
                _decodeDate(row['created_at'] as int?) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            deadline: _decodeDate(row['deadline'] as int?),
            data: _decodeMap(row['data'] as String?),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final nowInstant = _clock.now();
    final now = nowInstant.millisecondsSinceEpoch;
    final cancellation = jsonEncode({
      'reason': reason ?? 'cancelled',
      'cancelledAt': nowInstant.toIso8601String(),
    });
    _deleteWatcher(runId);
    _db.execute(
      'UPDATE wf_runs SET status = ?, suspension_data = NULL, wait_topic = NULL, '
      'resume_at = NULL, cancellation_data = ?, updated_at = ? WHERE id = ?',
      [WorkflowStatus.cancelled.name, cancellation, now, runId],
    );
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    _deleteWatcher(runId);
    final stepRows = _db.select(
      'SELECT name, value FROM wf_steps WHERE run_id = ? ORDER BY rowid',
      [runId],
    );
    final names = stepRows.map((row) => row['name'] as String).toList();
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
    final keep = <Map<String, Object?>>[];
    for (var i = 0; i < stepRows.length; i++) {
      final baseIndex = entryIndexes[i];
      if (baseIndex < targetIndex) {
        keep.add(stepRows[i]);
      } else {
        break;
      }
    }
    _db.execute('DELETE FROM wf_steps WHERE run_id = ?', [runId]);
    for (final row in keep) {
      _db.execute(
        'INSERT OR REPLACE INTO wf_steps(run_id, name, value) VALUES(?, ?, ?)',
        [runId, row['name'], row['value']],
      );
    }
    const iterations = 0;
    _db.execute(
      'UPDATE wf_runs SET status = ?, wait_topic = NULL, resume_at = NULL, '
      'suspension_data = ? WHERE id = ?',
      [
        WorkflowStatus.suspended.name,
        jsonEncode({
          'step': stepName,
          'iteration': iterations,
          'iterationStep': stepName,
        }),
        runId,
      ],
    );
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
  }) async {
    final conditions = <String>[];
    final params = <Object?>[];
    if (workflow != null) {
      conditions.add('workflow = ?');
      params.add(workflow);
    }
    if (status != null) {
      conditions.add('status = ?');
      params.add(status.name);
    }
    final buffer = StringBuffer('SELECT id FROM wf_runs');
    if (conditions.isNotEmpty) {
      buffer.write(' WHERE ${conditions.join(' AND ')}');
    }
    buffer.write(' ORDER BY rowid DESC LIMIT ?');
    params.add(limit);

    final ids = _db
        .select(buffer.toString(), params)
        .map((row) => row['id'] as String)
        .toList(growable: false);
    final results = <RunState>[];
    for (final id in ids) {
      final state = await get(id);
      if (state != null) {
        results.add(state);
      }
    }
    return results;
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    final rows = _db.select(
      'SELECT name, value FROM wf_steps WHERE run_id = ? ORDER BY rowid',
      [runId],
    );
    final entries = <WorkflowStepEntry>[];
    var position = 0;
    for (final row in rows) {
      entries.add(
        WorkflowStepEntry(
          name: row['name'] as String,
          value: _decode(row['value'] as String?),
          position: position,
        ),
      );
      position += 1;
    }
    return entries;
  }

  Future<void> close() async {
    _db.close();
  }

  void _deleteWatcher(String runId) {
    _db.execute('DELETE FROM wf_watchers WHERE run_id = ?', [runId]);
  }

  Map<String, Object?> _decodeMap(String? input) {
    if (input == null) return const {};
    final decoded = jsonDecode(input);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  }

  Object? _decode(String? input) {
    if (input == null) return null;
    return jsonDecode(input);
  }

  DateTime? _decodeDate(int? millis) {
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _baseStepName(String name) {
    final index = name.indexOf('#');
    if (index == -1) return name;
    return name.substring(0, index);
  }
}
