import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../core/contracts.dart';
import '../postgres/postgres_client.dart';
import 'schedule_calculator.dart';

/// PostgreSQL-backed implementation of [ScheduleStore].
class PostgresScheduleStore implements ScheduleStore {
  PostgresScheduleStore._(
    this._client, {
    this.namespace = 'stem',
    this.schema = 'public',
    this.lockTtl = const Duration(seconds: 5),
    ScheduleCalculator? calculator,
  }) : _calculator = calculator ?? ScheduleCalculator();

  final PostgresClient _client;
  final String namespace;
  final String schema;
  final Duration lockTtl;
  final ScheduleCalculator _calculator;

  bool _closed = false;

  /// Connects to a PostgreSQL database and initializes the schedule tables.
  ///
  /// The [uri] should be in the format:
  /// `postgresql://username:password@host:port/database`
  static Future<PostgresScheduleStore> connect(
    String uri, {
    String namespace = 'stem',
    String schema = 'public',
    Duration lockTtl = const Duration(seconds: 5),
    ScheduleCalculator? calculator,
    String? applicationName,
  }) async {
    final client = PostgresClient(uri, applicationName: applicationName);
    final store = PostgresScheduleStore._(
      client,
      namespace: namespace,
      schema: schema,
      lockTtl: lockTtl,
      calculator: calculator,
    );
    await store._initializeTables();
    return store;
  }

  /// Initializes the database schema with the schedule tables.
  Future<void> _initializeTables() async {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';

    await _client.run((Connection conn) async {
      // Schedule entries table
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}schedule_entries (
          id TEXT PRIMARY KEY,
          task_name TEXT NOT NULL,
          queue TEXT NOT NULL,
          spec TEXT NOT NULL,
          args JSONB NOT NULL DEFAULT '{}'::jsonb,
          enabled BOOLEAN NOT NULL DEFAULT true,
          jitter_ms INTEGER,
          last_run_at TIMESTAMPTZ,
          next_run_at TIMESTAMPTZ NOT NULL,
          last_jitter_ms INTEGER,
          last_error TEXT,
          timezone TEXT,
          meta JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}schedule_entries_next_run_at_idx
        ON $schema.${prefix}schedule_entries(next_run_at)
        WHERE enabled = true
      ''');

      // Schedule locks table for distributed locking
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}schedule_locks (
          id TEXT PRIMARY KEY,
          locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          expires_at TIMESTAMPTZ NOT NULL
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}schedule_locks_expires_at_idx
        ON $schema.${prefix}schedule_locks(expires_at)
      ''');
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.close();
  }

  String _entriesTable() {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    return '$schema.${prefix}schedule_entries';
  }

  String _locksTable() {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    return '$schema.${prefix}schedule_locks';
  }

  ScheduleEntry _entryFromRow(List<dynamic> row) {
    return ScheduleEntry(
      id: row[0] as String,
      taskName: row[1] as String,
      queue: row[2] as String,
      spec: row[3] as String,
      args: _decodeMap(row[4]),
      enabled: row[5] as bool,
      jitter: row[6] != null ? Duration(milliseconds: row[6] as int) : null,
      lastRunAt: row[7] as DateTime?,
      nextRunAt: row[8] as DateTime?,
      lastJitter: row[9] != null ? Duration(milliseconds: row[9] as int) : null,
      lastError: row[10] as String?,
      timezone: row[11] as String?,
      meta: _decodeMap(row[12]),
    );
  }

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) async {
    return _client.run((Connection conn) async {
      // Clean up expired locks first
      await conn.execute('''
        DELETE FROM ${_locksTable()}
        WHERE expires_at < NOW()
      ''');

      // Find due entries and acquire locks
      final result = await conn.execute(
        Sql.named('''
        SELECT
          e.id, e.task_name, e.queue, e.spec, e.args, e.enabled,
          e.jitter_ms, e.last_run_at, e.next_run_at, e.last_jitter_ms,
          e.last_error, e.timezone, e.meta
        FROM ${_entriesTable()} e
        LEFT JOIN ${_locksTable()} l ON e.id = l.id
        WHERE e.enabled = true
          AND e.next_run_at <= @now
          AND l.id IS NULL
        ORDER BY e.next_run_at ASC
        LIMIT @limit
        '''),
        parameters: {'now': now, 'limit': limit},
      );

      final entries = <ScheduleEntry>[];
      final expiresAt = DateTime.now().add(lockTtl);

      for (final row in result) {
        final id = row[0] as String;

        // Try to acquire lock
        try {
          await conn.execute(
            Sql.named('''
            INSERT INTO ${_locksTable()} (id, expires_at)
            VALUES (@id, @expires_at)
            '''),
            parameters: {'id': id, 'expires_at': expiresAt},
          );

          entries.add(_entryFromRow(row));
        } catch (_) {
          // Failed to acquire lock, skip this entry
          continue;
        }
      }

      return entries;
    });
  }

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    final now = DateTime.now();
    final nextRun =
        entry.nextRunAt ??
        _calculator.nextRun(
          entry,
          entry.lastRunAt ?? now,
          includeJitter: false,
        );

    await _client.run((Connection conn) async {
      final argsJson = jsonEncode(entry.args);
      final metaJson = jsonEncode(entry.meta);

      await conn.execute(
        Sql.named('''
        INSERT INTO ${_entriesTable()}
          (id, task_name, queue, spec, args, enabled, jitter_ms,
           last_run_at, next_run_at, last_jitter_ms, last_error, timezone, meta, updated_at)
        VALUES
          (@id, @task_name, @queue, @spec, @args::jsonb, @enabled, @jitter_ms,
           @last_run_at, @next_run_at, @last_jitter_ms, @last_error, @timezone, @meta::jsonb, NOW())
        ON CONFLICT (id)
        DO UPDATE SET
          task_name = EXCLUDED.task_name,
          queue = EXCLUDED.queue,
          spec = EXCLUDED.spec,
          args = EXCLUDED.args,
          enabled = EXCLUDED.enabled,
          jitter_ms = EXCLUDED.jitter_ms,
          last_run_at = EXCLUDED.last_run_at,
          next_run_at = EXCLUDED.next_run_at,
          last_jitter_ms = EXCLUDED.last_jitter_ms,
          last_error = EXCLUDED.last_error,
          timezone = EXCLUDED.timezone,
          meta = EXCLUDED.meta,
          updated_at = NOW()
        '''),
        parameters: {
          'id': entry.id,
          'task_name': entry.taskName,
          'queue': entry.queue,
          'spec': entry.spec,
          'args': argsJson,
          'enabled': entry.enabled,
          'jitter_ms': entry.jitter?.inMilliseconds,
          'last_run_at': entry.lastRunAt,
          'next_run_at': nextRun,
          'last_jitter_ms': entry.lastJitter?.inMilliseconds,
          'last_error': entry.lastError,
          'timezone': entry.timezone,
          'meta': metaJson,
        },
      );

      // Release lock if it exists
      await conn.execute(
        Sql.named('''
        DELETE FROM ${_locksTable()}
        WHERE id = @id
        '''),
        parameters: {'id': entry.id},
      );
    });
  }

  @override
  Future<void> remove(String id) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
        DELETE FROM ${_entriesTable()}
        WHERE id = @id
        '''),
        parameters: {'id': id},
      );

      await conn.execute(
        Sql.named('''
        DELETE FROM ${_locksTable()}
        WHERE id = @id
        '''),
        parameters: {'id': id},
      );
    });
  }

  @override
  Future<List<ScheduleEntry>> list({int? limit}) async {
    return _client.run((Connection conn) async {
      final query = limit != null
          ? '''
            SELECT
              id, task_name, queue, spec, args, enabled, jitter_ms,
              last_run_at, next_run_at, last_jitter_ms, last_error, timezone, meta
            FROM ${_entriesTable()}
            ORDER BY next_run_at ASC
            LIMIT @limit
            '''
          : '''
            SELECT
              id, task_name, queue, spec, args, enabled, jitter_ms,
              last_run_at, next_run_at, last_jitter_ms, last_error, timezone, meta
            FROM ${_entriesTable()}
            ORDER BY next_run_at ASC
            ''';

      final result = limit != null
          ? await conn.execute(Sql.named(query), parameters: {'limit': limit})
          : await conn.execute(query);

      return result.map((row) => _entryFromRow(row)).toList();
    });
  }

  @override
  Future<ScheduleEntry?> get(String id) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named('''
        SELECT
          id, task_name, queue, spec, args, enabled, jitter_ms,
          last_run_at, next_run_at, last_jitter_ms, last_error, timezone, meta
        FROM ${_entriesTable()}
        WHERE id = @id
        '''),
        parameters: {'id': id},
      );

      if (result.isEmpty) return null;

      return _entryFromRow(result.first);
    });
  }

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
  }) async {
    await _client.run((Connection conn) async {
      // Fetch current entry
      final result = await conn.execute(
        Sql.named('''
        SELECT
          id, task_name, queue, spec, args, enabled, jitter_ms,
          last_run_at, next_run_at, last_jitter_ms, last_error, timezone, meta
        FROM ${_entriesTable()}
        WHERE id = @id
        '''),
        parameters: {'id': id},
      );

      if (result.isEmpty) {
        // Release lock if entry doesn't exist
        await conn.execute(
          Sql.named('''
          DELETE FROM ${_locksTable()}
          WHERE id = @id
          '''),
          parameters: {'id': id},
        );
        return;
      }

      final entry = _entryFromRow(result.first);
      final next = _calculator.nextRun(
        entry.copyWith(lastRunAt: executedAt),
        executedAt,
        includeJitter: false,
      );

      await conn.execute(
        Sql.named('''
        UPDATE ${_entriesTable()}
        SET
          last_run_at = @last_run_at,
          next_run_at = @next_run_at,
          last_jitter_ms = @last_jitter_ms,
          last_error = @last_error,
          updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {
          'id': id,
          'last_run_at': executedAt,
          'next_run_at': next,
          'last_jitter_ms': jitter?.inMilliseconds,
          'last_error': lastError,
        },
      );

      // Release lock
      await conn.execute(
        Sql.named('''
        DELETE FROM ${_locksTable()}
        WHERE id = @id
        '''),
        parameters: {'id': id},
      );
    });
  }
}

Map<String, Object?> _decodeMap(Object? value) {
  if (value == null) return const {};
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  if (value is String) {
    return (jsonDecode(value) as Map).cast<String, Object?>();
  }
  return const {};
}
