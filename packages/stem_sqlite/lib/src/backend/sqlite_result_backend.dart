import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import 'package:stem_sqlite/src/connection.dart';
import 'package:stem_sqlite/src/models/models.dart';

/// SQLite-backed implementation of [ResultBackend].
class SqliteResultBackend implements ResultBackend {
  SqliteResultBackend._(
    this._connections, {
    required this.namespace,
    required this.defaultTtl,
    required this.groupDefaultTtl,
    required this.heartbeatTtl,
    required this.cleanupInterval,
  }) : _context = _connections.context {
    _startCleanupTimer();
  }

  /// Opens a SQLite backend from an existing database file.
  static Future<SqliteResultBackend> open(
    File file, {
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
    Duration cleanupInterval = const Duration(minutes: 1),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.open(file);
    return SqliteResultBackend._(
      connections,
      namespace: resolvedNamespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
      cleanupInterval: cleanupInterval,
    );
  }

  /// Connects to a SQLite database from a connection string (path URI).
  ///
  /// The [connectionString] should be in the format:
  /// `sqlite:///path/to/database.db` or `sqlite:///:memory:`
  ///
  /// If the parent directory doesn't exist, it will be created.
  ///
  /// Example:
  /// ```dart
  /// final backend = await SqliteResultBackend.connect(
  ///   connectionString: 'sqlite:///var/lib/app/stem.db',
  /// );
  /// ```
  static Future<SqliteResultBackend> connect({
    String? connectionString,
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
    Duration cleanupInterval = const Duration(minutes: 1),
  }) async {
    if (connectionString == null) {
      throw ArgumentError(
        'connectionString is required for SqliteResultBackend.connect(). '
        'Use open() to connect via ormed.yaml instead.',
      );
    }

    // Parse sqlite:// URIs
    var path = connectionString;
    if (connectionString.startsWith('sqlite://')) {
      path = connectionString.replaceFirst('sqlite://', '');
      // Handle sqlite:///:memory:
      if (path.startsWith(':')) {
        path = ':$path';
      }
    }

    final file = File(path);
    if (path != ':memory:' && !file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    return open(
      file,
      namespace: namespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
      cleanupInterval: cleanupInterval,
    );
  }

  final SqliteConnections _connections;
  final QueryContext _context;

  /// Namespace used to scope backend data.
  final String namespace;

  /// Default TTL applied to task results.
  final Duration defaultTtl;

  /// Default TTL applied to group metadata.
  final Duration groupDefaultTtl;

  /// TTL applied to worker heartbeat records.
  final Duration heartbeatTtl;

  /// Interval between cleanup passes.
  final Duration cleanupInterval;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  Timer? _cleanupTimer;
  bool _closed = false;

  /// Closes the backend and releases any database resources.
  @override
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

  /// Runs a cleanup cycle for tests.
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
    final expiresAt = now.add(ttl ?? defaultTtl);
    final status = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      meta: meta,
      attempt: attempt,
    );

    await _connections.runInTransaction((txn) async {
      final model = $StemTaskResult(
        id: taskId,
        namespace: namespace,
        state: state.name,
        payload: _wrapScalarJson(payload),
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
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final now = DateTime.now();
    final expiresAt = now.add(heartbeatTtl);
    await _connections.runInTransaction((txn) async {
      final model = StemWorkerHeartbeat(
        workerId: heartbeat.workerId,
        namespace: namespace,
        timestamp: heartbeat.timestamp,
        isolateCount: heartbeat.isolateCount,
        inflight: heartbeat.inflight,
        queues: {
          'items': heartbeat.queues.map((queue) => queue.toJson()).toList(),
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
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .firstOrNull();
    return row == null ? null : _heartbeatFromRow(row);
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    final now = DateTime.now();
    final rows = await _context
        .query<StemWorkerHeartbeat>()
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .orderBy('workerId')
        .get();
    return rows.map(_heartbeatFromRow).toList(growable: false);
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    final now = DateTime.now();
    final expiresAt = now.add(descriptor.ttl ?? groupDefaultTtl);
    await _connections.runInTransaction((txn) async {
      await txn.repository<StemGroup>().upsert(
        StemGroupInsertDto(
          id: descriptor.id,
          namespace: namespace,
          expected: descriptor.expected,
          meta: descriptor.meta,
          expiresAt: expiresAt,
        ),
        uniqueBy: ['id'],
      );
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
      final model = StemGroupResult(
        groupId: groupId,
        taskId: status.id,
        namespace: namespace,
        state: status.state.name,
        payload: _wrapScalarJson(status.payload),
        error: status.error?.toJson(),
        attempt: status.attempt,
        meta: status.meta,
      );
      await txn.repository<StemGroupResult>().upsert(
        model,
        uniqueBy: ['groupId', 'taskId'],
      );
    });

    return getGroup(groupId);
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
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
        payload: _unwrapScalarJson(row.payload),
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

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    final expiresAt = DateTime.now().add(ttl);
    await _context.repository<StemTaskResult>().update(
      StemTaskResultUpdateDto(expiresAt: expiresAt),
      where: StemTaskResultPartial(id: taskId, namespace: namespace),
    );
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
      if (row == null) {
        return false;
      }

      final meta = Map<String, Object?>.from(row.meta);
      if (meta['stem.chord.claimed'] == true) {
        return false;
      }
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

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      if (_closed) return;
      unawaited(_runCleanupCycle());
    });
  }

  Future<void> _runCleanupCycle() async {
    final now = DateTime.now();
    await _connections.runInTransaction((txn) async {
      await txn
          .query<StemTaskResult>()
          .whereEquals('namespace', namespace)
          .where('expiresAt', now, PredicateOperator.lessThanOrEqual)
          .delete();

      final expiredIds = await txn
          .query<StemGroup>()
          .whereEquals('namespace', namespace)
          .where('expiresAt', now, PredicateOperator.lessThanOrEqual)
          .pluck<String>('id');
      if (expiredIds.isNotEmpty) {
        await txn
            .query<StemGroup>()
            .whereIn('id', expiredIds)
            .whereEquals('namespace', namespace)
            .delete();
        await txn
            .query<StemGroupResult>()
            .whereIn('groupId', expiredIds)
            .whereEquals('namespace', namespace)
            .delete();
      }

      await txn
          .query<StemWorkerHeartbeat>()
          .whereEquals('namespace', namespace)
          .where('expiresAt', now, PredicateOperator.lessThanOrEqual)
          .delete();
    });
  }

  Future<bool> _groupExists(String groupId) async {
    final now = DateTime.now();
    return _context
        .query<StemGroup>()
        .whereEquals('id', groupId)
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .exists();
  }

  TaskStatus _taskStatusFromRow(StemTaskResult row) {
    final error = row.error is Map
        ? TaskError.fromJson((row.error! as Map).cast<String, Object?>())
        : null;
    return TaskStatus(
      id: row.id,
      state: TaskState.values.firstWhere((s) => s.name == row.state),
      payload: _unwrapScalarJson(row.payload),
      error: error,
      meta: row.meta,
      attempt: row.attempt,
    );
  }

  static const _scalarWrapperKey = '__wrapped_scalar__';

  Object? _wrapScalarJson(Object? value) {
    if (value == null) return null;
    if (value is Map || value is List) return value;
    return {_scalarWrapperKey: true, 'value': value};
  }

  Object? _unwrapScalarJson(Object? value) {
    if (value is Map && value[_scalarWrapperKey] == true) {
      return value['value'];
    }
    return value;
  }

  WorkerHeartbeat _heartbeatFromRow(StemWorkerHeartbeat row) {
    return WorkerHeartbeat(
      workerId: row.workerId,
      namespace: row.namespace,
      timestamp: row.timestamp,
      isolateCount: row.isolateCount,
      inflight: row.inflight,
      queues: _decodeHeartbeatQueues(row.queues),
      lastLeaseRenewal: row.lastLeaseRenewal,
      version: row.version,
      extras: row.extras,
    );
  }

  List<QueueHeartbeat> _decodeHeartbeatQueues(Object? raw) {
    if (raw == null) return const [];

    final List<Object?> items;
    if (raw is Map<Object?, Object?>) {
      final mapped = raw['items'];
      if (mapped is List) {
        items = mapped.cast<Object?>();
      } else {
        return const <QueueHeartbeat>[];
      }
    } else if (raw is List) {
      items = raw.cast<Object?>();
    } else {
      return const <QueueHeartbeat>[];
    }

    if (items.isEmpty) return const <QueueHeartbeat>[];
    return items
        .whereType<Map<Object?, Object?>>()
        .map((entry) => QueueHeartbeat.fromJson(entry.cast<String, Object?>()))
        .toList(growable: false);
  }
}
