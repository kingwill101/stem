import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:stem/stem.dart';

class SqliteWorkflowStore implements WorkflowStore {
  SqliteWorkflowStore._(this._db);

  final Database _db;

  factory SqliteWorkflowStore.open(File file) {
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
        suspension_data TEXT
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
    return SqliteWorkflowStore._(db);
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
  }) async {
    final id = 'wf-${DateTime.now().microsecondsSinceEpoch}-${_random()}';
    _db.execute(
      'INSERT INTO wf_runs(id, workflow, status, params) VALUES(?, ?, ?, ?)',
      [id, workflow, WorkflowStatus.running.name, jsonEncode(params)],
    );
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    final row = _db.select(
      'SELECT id, workflow, status, params, result, wait_topic, resume_at, '
      'last_error, suspension_data FROM wf_runs WHERE id = ?',
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
    _db.execute(
      'INSERT OR REPLACE INTO wf_steps(run_id, name, value) VALUES(?, ?, ?)',
      [runId, stepName, jsonEncode(value)],
    );
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = ?, wait_topic = NULL, '
      'suspension_data = ? WHERE id = ?',
      [
        WorkflowStatus.suspended.name,
        when.millisecondsSinceEpoch,
        jsonEncode(data),
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
    _db.execute(
      'UPDATE wf_runs SET status = ?, wait_topic = ?, resume_at = ?, '
      'suspension_data = ? WHERE id = ?',
      [
        WorkflowStatus.suspended.name,
        topic,
        deadline?.millisecondsSinceEpoch,
        jsonEncode(data),
        runId,
      ],
    );
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = NULL, wait_topic = NULL '
      'WHERE id = ?',
      [WorkflowStatus.running.name, runId],
    );
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    _db.execute(
      'UPDATE wf_runs SET status = ?, result = ?, suspension_data = NULL '
      'WHERE id = ?',
      [WorkflowStatus.completed.name, jsonEncode(result), runId],
    );
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    _db.execute('UPDATE wf_runs SET status = ?, last_error = ? WHERE id = ?', [
      (terminal ? WorkflowStatus.failed : WorkflowStatus.running).name,
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
      runId,
    ]);
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    _db.execute(
      'UPDATE wf_runs SET status = ?, resume_at = NULL, wait_topic = NULL, '
      'suspension_data = ? WHERE id = ?',
      [WorkflowStatus.running.name, jsonEncode(data), runId],
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
    final rows = _db.select(
      'SELECT id FROM wf_runs WHERE wait_topic = ? LIMIT ?',
      [topic, limit],
    );
    return rows.map((r) => r['id'] as String).toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    _db.execute(
      'UPDATE wf_runs SET status = ?, suspension_data = NULL, wait_topic = NULL, resume_at = NULL WHERE id = ?',
      [WorkflowStatus.cancelled.name, runId],
    );
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
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
    _db.dispose();
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

  int _random() => DateTime.now().microsecondsSinceEpoch & 0xFFFF;
}
