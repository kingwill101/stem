import 'dart:async';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/models.dart';

/// PostgreSQL-backed implementation of [ResultBackend].
class PostgresResultBackend implements ResultBackend {

  /// Creates a backend using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  factory PostgresResultBackend.fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
  }) {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = PostgresConnections.fromDataSource(dataSource);
    final backend = PostgresResultBackend._(
      connections,
      namespace: resolvedNamespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    ).._startCleanupTimer();
    return backend;
  }
  PostgresResultBackend._(
    this._connections, {
    required this.namespace,
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
  }) : _context = _connections.context;

  final PostgresConnections _connections;
  final QueryContext _context;

  /// Namespace used to scope backend data.
  final String namespace;

  /// Default TTL applied to task results.
  final Duration defaultTtl;

  /// Default TTL applied to group metadata.
  final Duration groupDefaultTtl;

  /// TTL applied to worker heartbeat records.
  final Duration heartbeatTtl;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  Timer? _cleanupTimer;
  bool _closed = false;

  /// Connects to a PostgreSQL database and initializes the required tables.
  ///
  /// The [connectionString] should be in the format:
  /// `postgresql://username:password@host:port/database`
  ///
  /// If [connectionString] is not provided, the connection string will be read
  /// from ormed.yaml.
  ///
  /// Example:
  /// ```dart
  /// final backend = await PostgresResultBackend.connect(
  ///   connectionString: 'postgresql://user:pass@localhost:5432/mydb',
  /// );
  /// ```
  static Future<PostgresResultBackend> connect({
    String? connectionString,
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.open(
      connectionString: connectionString,
    );
    final backend = PostgresResultBackend._(
      connections,
      namespace: resolvedNamespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    ).._startCleanupTimer();
    return backend;
  }

  void _startCleanupTimer() {
    // Run cleanup every minute to remove expired records
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_cleanup());
    });
  }

  Future<void> _cleanup() async {
    if (_closed) return;
    try {
      final now = DateTime.now();
      await _connections.runInTransaction((txn) async {
        await txn
            .query<StemTaskResult>()
            .whereEquals('namespace', namespace)
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
        await txn
            .query<StemGroup>()
            .whereEquals('namespace', namespace)
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
        await txn
            .query<StemWorkerHeartbeat>()
            .whereEquals('namespace', namespace)
            .where('expiresAt', now, PredicateOperator.lessThan)
            .delete();
      });
    } on Object {
      // Ignore cleanup errors
    }
  }

  /// Closes the backend and releases any database resources.
  @override
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
        namespace: namespace,
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
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    if (row == null) return null;
    final error = row.error is Map<Object?, Object?>
        ? TaskError.fromJson(
            (row.error! as Map<Object?, Object?>).cast<String, Object?>(),
          )
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
            final controller = _watchers.remove(taskId);
            if (controller != null) {
              unawaited(controller.close());
            }
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
      final repository = txn.repository<StemGroup>();
      final inserted = await repository.insertOrIgnore(
        StemGroupInsertDto(
          id: descriptor.id,
          namespace: namespace,
          expected: descriptor.expected,
          meta: descriptor.meta,
          expiresAt: expiresAt,
        ),
      );

      if (inserted == 0) {
        // Update existing group - only update business fields.
        await repository.update(
          StemGroupUpdateDto(
            expected: descriptor.expected,
            meta: descriptor.meta,
            expiresAt: expiresAt,
          ),
          where: StemGroupPartial(id: descriptor.id, namespace: namespace),
        );
      }

      await txn
          .query<StemGroupResult>()
          .whereEquals('groupId', descriptor.id)
          .whereEquals('namespace', namespace)
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
          namespace: namespace,
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
      where: StemTaskResultPartial(id: taskId, namespace: namespace),
    );
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final expiresAt = DateTime.now().add(heartbeatTtl);
    await _connections.runInTransaction((txn) async {
      final model = StemWorkerHeartbeat(
        workerId: heartbeat.workerId,
        namespace: namespace,
        timestamp: heartbeat.timestamp,
        isolateCount: heartbeat.isolateCount,
        inflight: heartbeat.inflight,
        queues: {'items': heartbeat.queues.map((q) => q.toJson()).toList()},
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
        .whereEquals('namespace', namespace)
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
        .whereEquals('namespace', namespace)
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
      final row = await txn
          .query<StemGroup>()
          .whereEquals('id', groupId)
          .whereEquals('namespace', namespace)
          .firstOrNull();
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
        where: StemGroupPartial(id: groupId, namespace: namespace),
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
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .exists();
  }

  Future<GroupStatus?> _readGroup(String groupId) async {
    final now = DateTime.now();
    final groupRow = await _context
        .query<StemGroup>()
        .whereEquals('id', groupId)
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    if (groupRow == null) return null;

    final resultRows = await _context
        .query<StemGroupResult>()
        .whereEquals('groupId', groupId)
        .whereEquals('namespace', namespace)
        .get();
    final results = <String, TaskStatus>{};
    for (final row in resultRows) {
      final error = row.error is Map
          ? TaskError.fromJson((row.error! as Map).cast<String, Object?>())
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
    final items = mapped is List ? mapped.cast<Object?>() : const <Object?>[];
    final queues = items
        .whereType<Map<Object?, Object?>>()
        .map((entry) => QueueHeartbeat.fromJson(entry.cast<String, Object?>()))
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
