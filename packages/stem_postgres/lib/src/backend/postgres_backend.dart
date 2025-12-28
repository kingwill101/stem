import 'dart:async';
// No JSON helpers needed; Ormed models handle serialization

import 'package:stem/stem.dart';
import 'package:ormed/ormed.dart';

import '../connection.dart';
import '../database/models/models.dart';

/// PostgreSQL-backed implementation of [ResultBackend].
class PostgresResultBackend implements ResultBackend {
  PostgresResultBackend._(
    this._connections, {
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
  }) : _context = _connections.context;

  final PostgresConnections _connections;
  final QueryContext _context;
  final Duration defaultTtl;
  final Duration groupDefaultTtl;
  final Duration heartbeatTtl;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  Timer? _cleanupTimer;
  bool _closed = false;

  /// Connects to a PostgreSQL database and initializes the required tables.
  ///
  /// The [connectionString] should be in the format:
  /// `postgresql://username:password@host:port/database`
  ///
  /// If [connectionString] is not provided, the connection string will be read from ormed.yaml.
  ///
  /// Example:
  /// ```dart
  /// final backend = await PostgresResultBackend.connect(
  ///   connectionString: 'postgresql://user:pass@localhost:5432/mydb',
  /// );
  /// ```
  static Future<PostgresResultBackend> connect({
    String? connectionString,
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
  }) async {
    final connections = await PostgresConnections.open(
      connectionString: connectionString,
    );
    final backend = PostgresResultBackend._(
      connections,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    );
    backend._startCleanupTimer();
    return backend;
  }

  void _startCleanupTimer() {
    // Run cleanup every minute to remove expired records
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanup();
    });
  }

  Future<void> _cleanup() async {
    if (_closed) return;
    try {
      final now = DateTime.now();
      await _connections.runInTransaction((txn) async {
        await txn
            .query<StemTaskResult>()
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
        await txn
            .query<StemGroup>()
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
        await txn
            .query<StemWorkerHeartbeat>()
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
      });
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  // ignore: unused_element
  String _tableName(String table) => table;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();

    await _connections.close();
  }

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
    final status = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      attempt: attempt,
      meta: meta,
    );

    final expiresAt = DateTime.now().add(ttl ?? defaultTtl);
    await _connections.runInTransaction((txn) async {
      final model = $StemTaskResult(
        id: taskId,
        state: state.name,
        payload: payload,
        error: error?.toJson(),
        attempt: attempt,
        meta: meta,
        expiresAt: expiresAt,
      ).toTracked();
      await txn.repository<StemTaskResult>().upsert(model, uniqueBy: ['id']);
    });

    _watchers[taskId]?.add(status);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final now = DateTime.now();
    final row = await _context
        .query<StemTaskResult>()
        .whereEquals('id', taskId)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    if (row == null) return null;
    final error = row.error is Map
        ? TaskError.fromJson((row.error as Map).cast<String, Object?>())
        : null;
    return TaskStatus(
      id: row.id,
      state: TaskState.values.firstWhere((s) => s.name == row.state),
      payload: row.payload,
      error: error,
      attempt: row.attempt,
      meta: row.meta,
    );
  }

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _watchers.putIfAbsent(
      taskId,
      () => StreamController<TaskStatus>.broadcast(
        onCancel: () {
          if (!(_watchers[taskId]?.hasListener ?? false)) {
            _watchers.remove(taskId)?.close();
          }
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    final now = DateTime.now();
    final expiresAt = now.add(descriptor.ttl ?? groupDefaultTtl);
    await _connections.runInTransaction((txn) async {
      // Try to find existing group first
      final existing = await txn
          .query<StemGroup>()
          .whereEquals('id', descriptor.id)
          .first();
      
      if (existing == null) {
        // Insert new group - timestamps will use DEFAULT
        await txn.repository<StemGroup>().insert(
          StemGroupInsertDto(
            id: descriptor.id,
            expected: descriptor.expected,
            meta: descriptor.meta,
            expiresAt: expiresAt,
          ),
        );
      } else {
        // Update existing group - only update business fields
        await txn.repository<StemGroup>().update(
          StemGroupUpdateDto(
            expected: descriptor.expected,
            meta: descriptor.meta,
            expiresAt: expiresAt,
          ),
          where: StemGroupPartial(id: descriptor.id),
        );
      }
      
      await txn
          .query<StemGroupResult>()
          .whereEquals('groupId', descriptor.id)
          .delete();
    });
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final exists = await _groupExists(groupId);
    if (!exists) return null;
    await _connections.runInTransaction((txn) async {
      await txn.repository<StemGroupResult>().upsert(
        StemGroupResultInsertDto(
          groupId: groupId,
          taskId: status.id,
          state: status.state.name,
          payload: status.payload,
          error: status.error?.toJson(),
          attempt: status.attempt,
          meta: status.meta,
        ),
        uniqueBy: ['groupId', 'taskId'],
      );
    });
    return getGroup(groupId);
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    return _readGroup(groupId);
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    final expiresAt = DateTime.now().add(ttl);

    await _context.repository<StemTaskResult>().update(
      StemTaskResultUpdateDto(expiresAt: expiresAt),
      where: StemTaskResultPartial(id: taskId),
    );
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final expiresAt = DateTime.now().add(heartbeatTtl);
    await _connections.runInTransaction((txn) async {
      final model = StemWorkerHeartbeat(
        workerId: heartbeat.workerId,
        namespace: heartbeat.namespace,
        timestamp: heartbeat.timestamp,
        isolateCount: heartbeat.isolateCount,
        inflight: heartbeat.inflight,
        queues: {
          'items': heartbeat.queues.map((q) => q.toJson()).toList(),
        },
        lastLeaseRenewal: heartbeat.lastLeaseRenewal,
        version: heartbeat.version,
        extras: heartbeat.extras,
        expiresAt: expiresAt,
      ).toTracked();
      await txn.repository<StemWorkerHeartbeat>().upsert(
        model,
        uniqueBy: ['workerId'],
      );
    });
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    final now = DateTime.now();
    final row = await _context
        .query<StemWorkerHeartbeat>()
        .whereEquals('workerId', workerId)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    if (row == null) return null;
    return _heartbeatFromRow(row);
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    final now = DateTime.now();
    final rows = await _context
        .query<StemWorkerHeartbeat>()
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .orderBy('timestamp', descending: true)
        .get();
    return rows.map(_heartbeatFromRow).toList(growable: false);
  }

  @override
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  }) async {
    return _connections.runInTransaction((txn) async {
      final row =
          await txn.query<StemGroup>().whereEquals('id', groupId).firstOrNull();
      if (row == null) return false;
      final meta = Map<String, Object?>.from(row.meta);
      if (meta['stem.chord.claimed'] == true) return false;
      meta['stem.chord.claimed'] = true;
      if (callbackTaskId != null) {
        meta[ChordMetadata.callbackTaskId] = callbackTaskId;
      }
      if (dispatchedAt != null) {
        meta[ChordMetadata.dispatchedAt] = dispatchedAt.toIso8601String();
      }
      await txn.repository<StemGroup>().update(
        StemGroupUpdateDto(meta: meta),
        where: StemGroupPartial(id: groupId),
      );
      return true;
    });
  }

  // Removed legacy JSON decoder (not needed with Ormed models)

  Future<bool> _groupExists(String groupId) async {
    final now = DateTime.now();
    return _context
        .query<StemGroup>()
        .whereEquals('id', groupId)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .exists();
  }

  Future<GroupStatus?> _readGroup(String groupId) async {
    final now = DateTime.now();
    final groupRow = await _context
        .query<StemGroup>()
        .whereEquals('id', groupId)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    if (groupRow == null) return null;

    final resultRows = await _context
        .query<StemGroupResult>()
        .whereEquals('groupId', groupId)
        .get();
    final results = <String, TaskStatus>{};
    for (final row in resultRows) {
      final error = row.error is Map
          ? TaskError.fromJson((row.error as Map).cast<String, Object?>())
          : null;
      results[row.taskId] = TaskStatus(
        id: row.taskId,
        state: TaskState.values.firstWhere((s) => s.name == row.state),
        payload: row.payload,
        error: error,
        meta: row.meta,
        attempt: row.attempt,
      );
    }

    return GroupStatus(
      id: groupRow.id,
      expected: groupRow.expected,
      results: results,
      meta: groupRow.meta,
    );
  }

  WorkerHeartbeat _heartbeatFromRow(StemWorkerHeartbeat row) {
    final raw = row.queues; // Map<String, Object?> by schema
    final mapped = raw['items'];
    final List<dynamic> items = mapped is List ? mapped : const [];
    final queues = items
        .whereType<Map>()
        .map((e) => QueueHeartbeat.fromJson(e.cast<String, Object?>()))
        .toList(growable: false);
    return WorkerHeartbeat(
      workerId: row.workerId,
      namespace: row.namespace,
      timestamp: row.timestamp,
      isolateCount: row.isolateCount,
      inflight: row.inflight,
      queues: queues,
      lastLeaseRenewal: row.lastLeaseRenewal,
      version: row.version,
      extras: row.extras,
    );
  }
}
