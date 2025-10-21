import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../core/contracts.dart';
import '../observability/heartbeat.dart';
import '../postgres/postgres_client.dart';

/// PostgreSQL-backed implementation of [ResultBackend].
class PostgresResultBackend implements ResultBackend {
  PostgresResultBackend._(
    this._client, {
    this.schema = 'public',
    this.namespace = 'stem',
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
  });

  final PostgresClient _client;
  final String schema;
  final String namespace;
  final Duration defaultTtl;
  final Duration groupDefaultTtl;
  final Duration heartbeatTtl;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  Timer? _cleanupTimer;
  bool _closed = false;

  /// Connects to a PostgreSQL database and initializes the required tables.
  ///
  /// The [uri] should be in the format:
  /// `postgresql://username:password@host:port/database`
  ///
  /// Example:
  /// ```dart
  /// final backend = await PostgresResultBackend.connect(
  ///   'postgresql://user:pass@localhost:5432/mydb',
  /// );
  /// ```
  static Future<PostgresResultBackend> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
    Duration heartbeatTtl = const Duration(seconds: 60),
    String? applicationName,
  }) async {
    final client = PostgresClient(uri, applicationName: applicationName);

    final backend = PostgresResultBackend._(
      client,
      schema: schema,
      namespace: namespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    );

    await backend._initializeTables();
    backend._startCleanupTimer();

    return backend;
  }

  /// Initializes the database schema with required tables.
  Future<void> _initializeTables() async {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';

    await _client.run((Connection conn) async {
      // Task results table
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}task_results (
          id TEXT PRIMARY KEY,
          state TEXT NOT NULL,
          payload JSONB,
          error JSONB,
          attempt INTEGER NOT NULL DEFAULT 0,
          meta JSONB NOT NULL DEFAULT '{}'::jsonb,
          expires_at TIMESTAMPTZ NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}task_results_expires_at_idx
        ON $schema.${prefix}task_results(expires_at)
      ''');

      // Groups table
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}groups (
          id TEXT PRIMARY KEY,
          expected INTEGER NOT NULL,
          meta JSONB NOT NULL DEFAULT '{}'::jsonb,
          expires_at TIMESTAMPTZ NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}groups_expires_at_idx
        ON $schema.${prefix}groups(expires_at)
      ''');

      // Group results table
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}group_results (
          group_id TEXT NOT NULL,
          task_id TEXT NOT NULL,
          state TEXT NOT NULL,
          payload JSONB,
          error JSONB,
          attempt INTEGER NOT NULL DEFAULT 0,
          meta JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          PRIMARY KEY (group_id, task_id),
          FOREIGN KEY (group_id) REFERENCES $schema.${prefix}groups(id) ON DELETE CASCADE
        )
      ''');

      // Worker heartbeats table
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}worker_heartbeats (
          worker_id TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          timestamp TIMESTAMPTZ NOT NULL,
          isolate_count INTEGER NOT NULL,
          inflight INTEGER NOT NULL,
          queues JSONB NOT NULL DEFAULT '[]'::jsonb,
          last_lease_renewal TIMESTAMPTZ,
          version TEXT NOT NULL,
          extras JSONB NOT NULL DEFAULT '{}'::jsonb,
          expires_at TIMESTAMPTZ NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}worker_heartbeats_expires_at_idx
        ON $schema.${prefix}worker_heartbeats(expires_at)
      ''');
    });
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
      final prefix = namespace.isNotEmpty ? '${namespace}_' : '';

      await _client.run((Connection conn) async {
        // Clean up expired task results
        await conn.execute('''
          DELETE FROM $schema.${prefix}task_results
          WHERE expires_at < NOW()
        ''');

        // Clean up expired groups (cascade will handle group_results)
        await conn.execute('''
          DELETE FROM $schema.${prefix}groups
          WHERE expires_at < NOW()
        ''');

        // Clean up expired worker heartbeats
        await conn.execute('''
          DELETE FROM $schema.${prefix}worker_heartbeats
          WHERE expires_at < NOW()
        ''');
      });
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  String _tableName(String table) {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    return (StringBuffer(schema)
          ..write('.')
          ..write(prefix)
          ..write(table))
        .toString();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();

    await _client.close();
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
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named(
          '''
        INSERT INTO ${_tableName('task_results')}
          (id, state, payload, error, attempt, meta, expires_at, updated_at)
        VALUES
          (@id, @state, @payload::jsonb, @error::jsonb, @attempt, @meta::jsonb, @expires_at, NOW())
        ON CONFLICT (id)
        DO UPDATE SET
          state = EXCLUDED.state,
          payload = EXCLUDED.payload,
          error = EXCLUDED.error,
          attempt = EXCLUDED.attempt,
          meta = EXCLUDED.meta,
          expires_at = EXCLUDED.expires_at,
          updated_at = NOW()
        ''',
        ),
        parameters: {
          'id': taskId,
          'state': state.name,
          'payload': payload != null ? jsonEncode(payload) : null,
          'error': error != null ? jsonEncode(error.toJson()) : null,
          'attempt': attempt,
          'meta': jsonEncode(meta),
          'expires_at': expiresAt,
        },
      );
    });

    _watchers[taskId]?.add(status);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named(
          '''
        SELECT id, state, payload, error, attempt, meta
        FROM ${_tableName('task_results')}
        WHERE id = @id AND expires_at > NOW()
        ''',
        ),
        parameters: {'id': taskId},
      );

      if (result.isEmpty) return null;

      final row = result.first;
      return TaskStatus(
        id: row[0] as String,
        state: TaskState.values.firstWhere((s) => s.name == row[1] as String),
        payload: _decodeJson(row[2]),
        error: _decodeJson(row[3]) != null
            ? TaskError.fromJson(
                (_decodeJson(row[3]) as Map).cast<String, Object?>(),
              )
            : null,
        attempt: row[4] as int,
        meta: _decodeJson(row[5]) is Map
            ? (_decodeJson(row[5]) as Map).cast<String, Object?>()
            : const {},
      );
    });
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
    final expiresAt = DateTime.now().add(descriptor.ttl ?? groupDefaultTtl);
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named(
          '''
        INSERT INTO ${_tableName('groups')}
          (id, expected, meta, expires_at)
        VALUES
          (@id, @expected, @meta::jsonb, @expires_at)
        ON CONFLICT (id)
        DO UPDATE SET
          expected = EXCLUDED.expected,
          meta = EXCLUDED.meta,
          expires_at = EXCLUDED.expires_at
        ''',
        ),
        parameters: {
          'id': descriptor.id,
          'expected': descriptor.expected,
          'meta': jsonEncode(descriptor.meta),
          'expires_at': expiresAt,
        },
      );

      // Clear existing group results
      await conn.execute(
        Sql.named(
          '''
        DELETE FROM ${_tableName('group_results')}
        WHERE group_id = @group_id
        ''',
        ),
        parameters: {'group_id': descriptor.id},
      );
    });
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    return _client.run((Connection conn) async {
      final exists = await _groupExists(conn, groupId);
      if (!exists) return null;

      await conn.execute(
        Sql.named(
          '''
        INSERT INTO ${_tableName('group_results')}
          (group_id, task_id, state, payload, error, attempt, meta)
       VALUES
         (@group_id, @task_id, @state, @payload::jsonb, @error::jsonb, @attempt, @meta::jsonb)
       ON CONFLICT (group_id, task_id)
        DO UPDATE SET
          state = EXCLUDED.state,
          payload = EXCLUDED.payload,
          error = EXCLUDED.error,
          attempt = EXCLUDED.attempt,
          meta = EXCLUDED.meta
        ''',
        ),
        parameters: {
          'group_id': groupId,
          'task_id': status.id,
          'state': status.state.name,
          'payload': status.payload != null ? jsonEncode(status.payload) : null,
          'error': status.error != null
              ? jsonEncode(status.error!.toJson())
              : null,
          'attempt': status.attempt,
          'meta': jsonEncode(status.meta),
        },
      );

      return _readGroup(conn, groupId);
    });
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    return _client.run((Connection conn) async {
      return _readGroup(conn, groupId);
    });
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    final expiresAt = DateTime.now().add(ttl);

    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named(
          '''
        UPDATE ${_tableName('task_results')}
        SET expires_at = @expires_at
        WHERE id = @id
        ''',
        ),
        parameters: {'id': taskId, 'expires_at': expiresAt},
      );
    });
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final expiresAt = DateTime.now().add(heartbeatTtl);
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named(
          '''
        INSERT INTO ${_tableName('worker_heartbeats')}
          (worker_id, namespace, timestamp, isolate_count, inflight, queues, last_lease_renewal, version, extras, expires_at)
        VALUES
          (@worker_id, @namespace, @timestamp, @isolate_count, @inflight, @queues::jsonb, @last_lease_renewal, @version, @extras::jsonb, @expires_at)
        ON CONFLICT (worker_id)
        DO UPDATE SET
          namespace = EXCLUDED.namespace,
          timestamp = EXCLUDED.timestamp,
          isolate_count = EXCLUDED.isolate_count,
          inflight = EXCLUDED.inflight,
          queues = EXCLUDED.queues,
          last_lease_renewal = EXCLUDED.last_lease_renewal,
          version = EXCLUDED.version,
          extras = EXCLUDED.extras,
          expires_at = EXCLUDED.expires_at
        ''',
        ),
        parameters: {
          'worker_id': heartbeat.workerId,
          'namespace': heartbeat.namespace,
          'timestamp': heartbeat.timestamp,
          'isolate_count': heartbeat.isolateCount,
          'inflight': heartbeat.inflight,
          'queues': jsonEncode(
            heartbeat.queues.map((q) => q.toJson()).toList(),
          ),
          'last_lease_renewal': heartbeat.lastLeaseRenewal,
          'version': heartbeat.version,
          'extras': jsonEncode(heartbeat.extras),
          'expires_at': expiresAt,
        },
      );
    });
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named(
          '''
        SELECT worker_id, namespace, timestamp, isolate_count, inflight, queues, last_lease_renewal, version, extras
        FROM ${_tableName('worker_heartbeats')}
        WHERE worker_id = @worker_id AND expires_at > NOW()
        ''',
        ),
        parameters: {'worker_id': workerId},
      );

      if (result.isEmpty) return null;

      final row = result.first;
      final queuesData = (_decodeJson(row[5]) as List).cast<Map>();
      final queues = queuesData
          .map((q) => QueueHeartbeat.fromJson(q.cast<String, Object?>()))
          .toList();

      return WorkerHeartbeat(
        workerId: row[0] as String,
        namespace: row[1] as String,
        timestamp: row[2] as DateTime,
        isolateCount: row[3] as int,
        inflight: row[4] as int,
        queues: queues,
        lastLeaseRenewal: row[6] as DateTime?,
        version: row[7] as String,
        extras: (_decodeJson(row[8]) as Map).cast<String, Object?>(),
      );
    });
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    return _client.run((Connection conn) async {
      final result = await conn.execute('''
        SELECT worker_id, namespace, timestamp, isolate_count, inflight, queues, last_lease_renewal, version, extras
        FROM ${_tableName('worker_heartbeats')}
        WHERE expires_at > NOW()
        ORDER BY timestamp DESC
      ''');

      return result.map((row) {
        final queuesData = (_decodeJson(row[5]) as List).cast<Map>();
        final queues = queuesData
            .map((q) => QueueHeartbeat.fromJson(q.cast<String, Object?>()))
            .toList();

        return WorkerHeartbeat(
          workerId: row[0] as String,
          namespace: row[1] as String,
          timestamp: row[2] as DateTime,
          isolateCount: row[3] as int,
          inflight: row[4] as int,
          queues: queues,
          lastLeaseRenewal: row[6] as DateTime?,
          version: row[7] as String,
          extras: (_decodeJson(row[8]) as Map).cast<String, Object?>(),
        );
      }).toList();
    });
  }

  dynamic _decodeJson(Object? value) {
    if (value == null) return null;
    if (value is String) {
      if (value.isEmpty) return null;
      return jsonDecode(value);
    }
    if (value is Map || value is List) {
      return value;
    }
    return value;
  }

  Future<bool> _groupExists(Connection conn, String groupId) async {
    final result = await conn.execute(
      Sql.named(
        '''
      SELECT 1
      FROM ${_tableName('groups')}
      WHERE id = @id AND expires_at > NOW()
      ''',
      ),
      parameters: {'id': groupId},
    );
    return result.isNotEmpty;
  }

  Future<GroupStatus?> _readGroup(Connection conn, String groupId) async {
    final groupResult = await conn.execute(
      Sql.named(
        '''
      SELECT expected, meta
      FROM ${_tableName('groups')}
      WHERE id = @id AND expires_at > NOW()
      ''',
      ),
      parameters: {'id': groupId},
    );

    if (groupResult.isEmpty) return null;

    final groupRow = groupResult.first;
    final expected = groupRow[0] as int;
    final meta = _decodeJson(groupRow[1]) is Map
        ? (_decodeJson(groupRow[1]) as Map).cast<String, Object?>()
        : const <String, Object?>{};

    final resultsQuery = await conn.execute(
      Sql.named(
        '''
      SELECT task_id, state, payload, error, attempt, meta
      FROM ${_tableName('group_results')}
      WHERE group_id = @group_id
      ''',
      ),
      parameters: {'group_id': groupId},
    );

    final results = <String, TaskStatus>{};
    for (final row in resultsQuery) {
      final taskId = row[0] as String;
      results[taskId] = TaskStatus(
        id: taskId,
        state: TaskState.values.firstWhere((s) => s.name == row[1] as String),
        payload: _decodeJson(row[2]),
        error: _decodeJson(row[3]) != null
            ? TaskError.fromJson(
                (_decodeJson(row[3]) as Map).cast<String, Object?>(),
              )
            : null,
        attempt: row[4] as int,
        meta: _decodeJson(row[5]) is Map
            ? (_decodeJson(row[5]) as Map).cast<String, Object?>()
            : const {},
      );
    }

    return GroupStatus(
      id: groupId,
      expected: expected,
      results: results,
      meta: meta,
    );
  }
}
