import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:stem/stem.dart';

import '../connection.dart';
import '../database.dart';

class SqliteResultBackend implements ResultBackend {
  SqliteResultBackend._(
    this._connections, {
    required this.defaultTtl,
    required this.groupDefaultTtl,
    required this.heartbeatTtl,
    required this.cleanupInterval,
  }) : _db = _connections.db {
    _startCleanupTimer();
  }

  static Future<SqliteResultBackend> open(
    File file, {
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
    Duration cleanupInterval = const Duration(minutes: 1),
  }) async {
    final connections = await SqliteConnections.open(file);
    return SqliteResultBackend._(
      connections,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
      cleanupInterval: cleanupInterval,
    );
  }

  final SqliteConnections _connections;
  final StemSqliteDatabase _db;
  final Duration defaultTtl;
  final Duration groupDefaultTtl;
  final Duration heartbeatTtl;
  final Duration cleanupInterval;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  Timer? _cleanupTimer;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cleanupTimer?.cancel();
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();
    await _connections.close();
  }

  @visibleForTesting
  Future<void> runCleanup() => _runCleanupCycle();

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(ttl ?? defaultTtl).millisecondsSinceEpoch;
    final status = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      meta: meta,
      attempt: attempt,
      updatedAt: now,
    );

    await _connections.runInTransaction((txn) async {
      final companion = StemTaskResultsCompanion(
        id: Value(taskId),
        state: Value(state.name),
        payload: Value(_encodeJson(payload)),
        error: Value(error == null ? null : jsonEncode(error.toJson())),
        attempt: Value(attempt),
        meta: Value(jsonEncode(meta)),
        expiresAt: Value(expiresAt),
        createdAt: Value(now.millisecondsSinceEpoch),
        updatedAt: Value(now.millisecondsSinceEpoch),
      );
      await txn.into(txn.stemTaskResults).insertOnConflictUpdate(companion);
    });

    _watchers[taskId]?.add(status);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row =
        await (_db.select(_db.stemTaskResults)..where(
              (tbl) =>
                  tbl.id.equals(taskId) & tbl.expiresAt.isBiggerThanValue(now),
            ))
            .getSingleOrNull();
    return row == null ? null : _taskStatusFromRow(row);
  }

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _watchers.putIfAbsent(
      taskId,
      () => StreamController<TaskStatus>.broadcast(
        onCancel: () {
          final current = _watchers[taskId];
          if (current != null && !current.hasListener) {
            _watchers.remove(taskId)?.close();
          }
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final now = DateTime.now();
    final expiresAt = now.add(heartbeatTtl).millisecondsSinceEpoch;
    await _connections.runInTransaction((txn) async {
      final companion = StemWorkerHeartbeatsCompanion(
        workerId: Value(heartbeat.workerId),
        namespace: Value(heartbeat.namespace),
        timestamp: Value(heartbeat.timestamp.millisecondsSinceEpoch),
        isolateCount: Value(heartbeat.isolateCount),
        inflight: Value(heartbeat.inflight),
        queues: Value(
          jsonEncode(heartbeat.queues.map((queue) => queue.toJson()).toList()),
        ),
        lastLeaseRenewal: Value(
          heartbeat.lastLeaseRenewal?.millisecondsSinceEpoch,
        ),
        version: Value(heartbeat.version),
        extras: Value(jsonEncode(heartbeat.extras)),
        expiresAt: Value(expiresAt),
        createdAt: Value(now.millisecondsSinceEpoch),
      );
      await txn
          .into(txn.stemWorkerHeartbeats)
          .insertOnConflictUpdate(companion);
    });
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row =
        await (_db.select(_db.stemWorkerHeartbeats)..where(
              (tbl) =>
                  tbl.workerId.equals(workerId) &
                  tbl.expiresAt.isBiggerThanValue(now),
            ))
            .getSingleOrNull();
    return row == null ? null : _heartbeatFromRow(row);
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.stemWorkerHeartbeats)
              ..where((tbl) => tbl.expiresAt.isBiggerThanValue(now))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.workerId)]))
            .get();
    return rows.map(_heartbeatFromRow).toList(growable: false);
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    final now = DateTime.now();
    final expiresAt = now
        .add(descriptor.ttl ?? groupDefaultTtl)
        .millisecondsSinceEpoch;
    await _connections.runInTransaction((txn) async {
      final companion = StemGroupsCompanion(
        id: Value(descriptor.id),
        expected: Value(descriptor.expected),
        meta: Value(jsonEncode(descriptor.meta)),
        expiresAt: Value(expiresAt),
        createdAt: Value(now.millisecondsSinceEpoch),
      );
      await txn.into(txn.stemGroups).insertOnConflictUpdate(companion);
      final delete = txn.delete(txn.stemGroupResults)
        ..where((tbl) => tbl.groupId.equals(descriptor.id));
      await delete.go();
    });
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final exists = await _groupExists(groupId);
    if (!exists) return null;

    final now = DateTime.now();
    await _connections.runInTransaction((txn) async {
      final companion = StemGroupResultsCompanion(
        groupId: Value(groupId),
        taskId: Value(status.id),
        state: Value(status.state.name),
        payload: Value(_encodeJson(status.payload)),
        error: Value(
          status.error == null ? null : jsonEncode(status.error!.toJson()),
        ),
        attempt: Value(status.attempt),
        meta: Value(jsonEncode(status.meta)),
        createdAt: Value(now.millisecondsSinceEpoch),
      );
      await txn.into(txn.stemGroupResults).insertOnConflictUpdate(companion);
    });

    return getGroup(groupId);
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final groupRow =
        await (_db.select(_db.stemGroups)..where(
              (tbl) =>
                  tbl.id.equals(groupId) & tbl.expiresAt.isBiggerThanValue(now),
            ))
            .getSingleOrNull();
    if (groupRow == null) return null;

    final resultRows = await (_db.select(
      _db.stemGroupResults,
    )..where((tbl) => tbl.groupId.equals(groupId))).get();
    final results = <String, TaskStatus>{};
    for (final row in resultRows) {
      results[row.taskId] = TaskStatus(
        id: row.taskId,
        state: TaskState.values.firstWhere((s) => s.name == row.state),
        payload: _decodeJson(row.payload),
        error: row.error == null
            ? null
            : TaskError.fromJson(_decodeMap(row.error!)),
        meta: _decodeMap(row.meta),
        attempt: row.attempt,
      );
    }

    return GroupStatus(
      id: groupRow.id,
      expected: groupRow.expected,
      results: results,
      meta: _decodeMap(groupRow.meta),
    );
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    final expiresAt = DateTime.now().add(ttl).millisecondsSinceEpoch;
    await (_db.update(_db.stemTaskResults)
          ..where((tbl) => tbl.id.equals(taskId)))
        .write(StemTaskResultsCompanion(expiresAt: Value(expiresAt)));
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      if (_closed) return;
      unawaited(_runCleanupCycle());
    });
  }

  Future<void> _runCleanupCycle() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _connections.runInTransaction((txn) async {
      await txn.customUpdate(
        'DELETE FROM stem_task_results WHERE expires_at <= ?1',
        variables: [Variable.withInt(now)],
        updates: {txn.stemTaskResults},
      );

      final expiredGroups = await txn
          .customSelect(
            'SELECT id FROM stem_groups WHERE expires_at <= ?1',
            variables: [Variable.withInt(now)],
            readsFrom: {txn.stemGroups},
          )
          .get();
      if (expiredGroups.isNotEmpty) {
        final ids = expiredGroups
            .map((row) => row.data['id'] as String)
            .toList(growable: false);
        final placeholders = List.filled(ids.length, '?').join(', ');
        final variables = ids.map(Variable.withString).toList();
        await txn.customUpdate(
          'DELETE FROM stem_groups WHERE id IN ($placeholders)',
          variables: variables,
          updates: {txn.stemGroups},
        );
        await txn.customUpdate(
          'DELETE FROM stem_group_results WHERE group_id IN ($placeholders)',
          variables: variables,
          updates: {txn.stemGroupResults},
        );
      }

      await txn.customUpdate(
        'DELETE FROM stem_worker_heartbeats WHERE expires_at <= ?1',
        variables: [Variable.withInt(now)],
        updates: {txn.stemWorkerHeartbeats},
      );
    });
  }

  Future<bool> _groupExists(String groupId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM stem_groups WHERE id = ?1 AND expires_at > ?2',
          variables: [Variable.withString(groupId), Variable.withInt(now)],
          readsFrom: {_db.stemGroups},
        )
        .getSingle();
    return ((result.data['c'] as num?) ?? 0) > 0;
  }

  TaskStatus _taskStatusFromRow(StemTaskResult row) {
    return TaskStatus(
      id: row.id,
      state: TaskState.values.firstWhere((s) => s.name == row.state),
      payload: _decodeJson(row.payload),
      error: row.error == null
          ? null
          : TaskError.fromJson(_decodeMap(row.error!)),
      meta: _decodeMap(row.meta),
      attempt: row.attempt,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }

  WorkerHeartbeat _heartbeatFromRow(StemWorkerHeartbeat row) {
    return WorkerHeartbeat(
      workerId: row.workerId,
      namespace: row.namespace,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestamp),
      isolateCount: row.isolateCount,
      inflight: row.inflight,
      queues: _decodeHeartbeatQueues(row.queues),
      lastLeaseRenewal: row.lastLeaseRenewal == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastLeaseRenewal!),
      version: row.version,
      extras: _decodeMap(row.extras),
    );
  }

  String? _encodeJson(Object? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }

  Object? _decodeJson(String? value) {
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _decodeMap(String? value) {
    if (value == null || value.isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {
      // ignore malformed JSON and fall back to empty map
    }
    return const {};
  }

  List<QueueHeartbeat> _decodeHeartbeatQueues(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (entry) => QueueHeartbeat.fromJson(entry.cast<String, Object?>()),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // ignore malformed JSON and fall back to empty list
    }
    return const [];
  }
}
