import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../core/contracts.dart';
import '../postgres/postgres_client.dart';
import 'schedule_calculator.dart';
import 'schedule_spec.dart';

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

  static const String _selectColumns =
      'e.id, e.task_name, e.queue, e.spec, e.args, e.kwargs, e.enabled, '
      'e.jitter_ms, e.last_run_at, e.next_run_at, e.last_jitter_ms, '
      'e.last_error, e.timezone, e.total_run_count, e.last_success_at, '
      'e.last_error_at, e.drift_ms, e.expire_at, e.meta, e.created_at, e.updated_at';

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
          spec JSONB NOT NULL,
          args JSONB NOT NULL DEFAULT '{}'::jsonb,
          kwargs JSONB NOT NULL DEFAULT '{}'::jsonb,
          enabled BOOLEAN NOT NULL DEFAULT true,
          jitter_ms INTEGER,
          last_run_at TIMESTAMPTZ,
          next_run_at TIMESTAMPTZ NOT NULL,
          last_jitter_ms INTEGER,
          last_error TEXT,
          timezone TEXT,
          total_run_count BIGINT NOT NULL DEFAULT 0,
          last_success_at TIMESTAMPTZ,
          last_error_at TIMESTAMPTZ,
          drift_ms INTEGER,
          expire_at TIMESTAMPTZ,
          meta JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      try {
        await conn.execute('''
          ALTER TABLE $schema.${prefix}schedule_entries
          ALTER COLUMN spec TYPE JSONB
          USING CASE
            WHEN jsonb_typeof(spec::jsonb) IS NULL THEN to_jsonb(spec::text)
            ELSE spec::jsonb
          END
        ''');
      } catch (_) {}

      await _ensureColumn(
        conn,
        "ALTER TABLE $schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS kwargs JSONB NOT NULL DEFAULT '{}'::jsonb",
      );
      await _ensureColumn(
        conn,
        'ALTER TABLE '
        '$schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS total_run_count BIGINT NOT NULL DEFAULT 0',
      );
      await _ensureColumn(
        conn,
        'ALTER TABLE '
        '$schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS last_success_at TIMESTAMPTZ',
      );
      await _ensureColumn(
        conn,
        'ALTER TABLE '
        '$schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS last_error_at TIMESTAMPTZ',
      );
      await _ensureColumn(
        conn,
        'ALTER TABLE '
        '$schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS drift_ms INTEGER',
      );
      await _ensureColumn(
        conn,
        'ALTER TABLE '
        '$schema.${prefix}schedule_entries ADD COLUMN IF NOT EXISTS expire_at TIMESTAMPTZ',
      );

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

      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}schedule_run_history (
          schedule_id TEXT NOT NULL,
          scheduled_at TIMESTAMPTZ NOT NULL,
          executed_at TIMESTAMPTZ NOT NULL,
          success BOOLEAN NOT NULL,
          duration_ms INTEGER,
          error TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}schedule_run_history_idx
        ON $schema.${prefix}schedule_run_history(schedule_id, executed_at DESC)
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

  String _historyTable() {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    return '$schema.${prefix}schedule_run_history';
  }

  Future<void> _releaseLock(Connection conn, String id) async {
    await conn.execute(
      Sql.named('''
        DELETE FROM ${_locksTable()}
        WHERE id = @id
      '''),
      parameters: {'id': id},
    );
  }

  ScheduleEntry _entryFromRow(List<dynamic> row) {
    return ScheduleEntry(
      id: row[0] as String,
      taskName: row[1] as String,
      queue: row[2] as String,
      spec: ScheduleSpec.fromPersisted(row[3]),
      args: _decodeMap(row[4]),
      kwargs: _decodeMap(row[5]),
      enabled: row[6] as bool,
      jitter: row[7] != null
          ? Duration(milliseconds: (row[7] as num).toInt())
          : null,
      lastRunAt: row[8] as DateTime?,
      nextRunAt: row[9] as DateTime?,
      lastJitter: row[10] != null
          ? Duration(milliseconds: (row[10] as num).toInt())
          : null,
      lastError: row[11] as String?,
      timezone: row[12] as String?,
      totalRunCount: (row[13] as num?)?.toInt() ?? 0,
      lastSuccessAt: row[14] as DateTime?,
      lastErrorAt: row[15] as DateTime?,
      drift: row[16] != null
          ? Duration(milliseconds: (row[16] as num).toInt())
          : null,
      expireAt: row[17] as DateTime?,
      meta: _decodeMap(row[18]),
      createdAt: row.length > 19 ? row[19] as DateTime? : null,
      updatedAt: row.length > 20 ? row[20] as DateTime? : null,
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
        SELECT $_selectColumns
        FROM ${_entriesTable()} e
        LEFT JOIN ${_locksTable()} l ON e.id = l.id
        WHERE e.enabled = true
          AND e.next_run_at <= @now
          AND (e.expire_at IS NULL OR e.expire_at > @now)
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
    final now = DateTime.now().toUtc();
    DateTime? nextRun = entry.nextRunAt;
    if (entry.enabled) {
      nextRun ??= _calculator.nextRun(
        entry,
        entry.lastRunAt ?? now,
        includeJitter: false,
      );
    } else {
      nextRun ??= entry.lastRunAt ?? now;
    }

    await _client.run((Connection conn) async {
      final argsJson = jsonEncode(entry.args);
      final kwargsJson = jsonEncode(entry.kwargs);
      final specJson = jsonEncode(entry.spec.toJson());
      final metaJson = jsonEncode(entry.meta);

      await conn.execute(
        Sql.named('''
        INSERT INTO ${_entriesTable()}
          (id, task_name, queue, spec, args, kwargs, enabled, jitter_ms,
           last_run_at, next_run_at, last_jitter_ms, last_error, timezone, total_run_count,
           last_success_at, last_error_at, drift_ms, expire_at, meta, updated_at)
        VALUES
          (@id, @task_name, @queue, @spec::jsonb, @args::jsonb, @kwargs::jsonb, @enabled, @jitter_ms,
           @last_run_at, @next_run_at, @last_jitter_ms, @last_error, @timezone, @total_run_count,
           @last_success_at, @last_error_at, @drift_ms, @expire_at, @meta::jsonb, NOW())
        ON CONFLICT (id)
        DO UPDATE SET
          task_name = EXCLUDED.task_name,
          queue = EXCLUDED.queue,
          spec = EXCLUDED.spec,
          args = EXCLUDED.args,
          kwargs = EXCLUDED.kwargs,
          enabled = EXCLUDED.enabled,
          jitter_ms = EXCLUDED.jitter_ms,
          last_run_at = EXCLUDED.last_run_at,
          next_run_at = EXCLUDED.next_run_at,
          last_jitter_ms = EXCLUDED.last_jitter_ms,
          last_error = EXCLUDED.last_error,
          timezone = EXCLUDED.timezone,
          total_run_count = EXCLUDED.total_run_count,
          last_success_at = EXCLUDED.last_success_at,
          last_error_at = EXCLUDED.last_error_at,
          drift_ms = EXCLUDED.drift_ms,
          expire_at = EXCLUDED.expire_at,
          meta = EXCLUDED.meta,
          updated_at = NOW()
        '''),
        parameters: {
          'id': entry.id,
          'task_name': entry.taskName,
          'queue': entry.queue,
          'spec': specJson,
          'args': argsJson,
          'kwargs': kwargsJson,
          'enabled': entry.enabled,
          'jitter_ms': entry.jitter?.inMilliseconds,
          'last_run_at': entry.lastRunAt,
          'next_run_at': nextRun,
          'last_jitter_ms': entry.lastJitter?.inMilliseconds,
          'last_error': entry.lastError,
          'timezone': entry.timezone,
          'total_run_count': entry.totalRunCount,
          'last_success_at': entry.lastSuccessAt,
          'last_error_at': entry.lastErrorAt,
          'drift_ms': entry.drift?.inMilliseconds,
          'expire_at': entry.expireAt,
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
              $_selectColumns
            FROM ${_entriesTable()} e
            ORDER BY next_run_at ASC
            LIMIT @limit
            '''
          : '''
            SELECT
              $_selectColumns
            FROM ${_entriesTable()} e
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
          $_selectColumns
        FROM ${_entriesTable()} e
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
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    await _client.run((Connection conn) async {
      try {
        final result = await conn.execute(
          Sql.named('''
        SELECT $_selectColumns
        FROM ${_entriesTable()} e
        WHERE id = @id
        FOR UPDATE
        '''),
          parameters: {'id': id},
        );

        if (result.isEmpty) {
          return;
        }

        final entry = _entryFromRow(result.first);
        final bool resolvedSuccess = success && lastError == null;
        final updated = entry.copyWith(
          lastRunAt: executedAt,
          lastJitter: jitter,
          lastError: lastError,
          lastSuccessAt: resolvedSuccess ? executedAt : entry.lastSuccessAt,
          lastErrorAt: resolvedSuccess ? entry.lastErrorAt : executedAt,
          totalRunCount: entry.totalRunCount + 1,
          drift: drift ?? entry.drift,
        );

        DateTime? effectiveNextRun = nextRunAt;
        var enabled = updated.enabled;
        if (effectiveNextRun == null && enabled) {
          try {
            effectiveNextRun = _calculator.nextRun(
              updated,
              executedAt,
              includeJitter: false,
            );
          } catch (_) {
            effectiveNextRun = executedAt;
          }
        }

        if (updated.expireAt != null &&
            !executedAt.isBefore(updated.expireAt!)) {
          enabled = false;
        }
        if (updated.spec is ClockedScheduleSpec) {
          final spec = updated.spec as ClockedScheduleSpec;
          if (spec.runOnce && !executedAt.isBefore(spec.runAt)) {
            enabled = false;
          }
        }

        final nextValue = (effectiveNextRun ?? executedAt).toUtc();

        await conn.execute(
          Sql.named('''
        UPDATE ${_entriesTable()}
        SET
          last_run_at = @last_run_at,
          next_run_at = @next_run_at,
          last_jitter_ms = @last_jitter_ms,
          last_error = @last_error,
          timezone = @timezone,
          total_run_count = @total_run_count,
          last_success_at = @last_success_at,
          last_error_at = @last_error_at,
          drift_ms = @drift_ms,
          enabled = @enabled,
          updated_at = NOW()
        WHERE id = @id
        '''),
          parameters: {
            'id': id,
            'last_run_at': executedAt,
            'next_run_at': nextValue,
            'last_jitter_ms': jitter?.inMilliseconds,
            'last_error': lastError,
            'timezone': updated.timezone,
            'total_run_count': updated.totalRunCount,
            'last_success_at': updated.lastSuccessAt,
            'last_error_at': updated.lastErrorAt,
            'drift_ms': updated.drift?.inMilliseconds,
            'enabled': enabled,
          },
        );

        await conn.execute(
          Sql.named('''
        INSERT INTO ${_historyTable()} (
          schedule_id,
          scheduled_at,
          executed_at,
          success,
          duration_ms,
          error
        ) VALUES (
          @schedule_id,
          @scheduled_at,
          @executed_at,
          @success,
          @duration_ms,
          @error
        )
        '''),
          parameters: {
            'schedule_id': id,
            'scheduled_at': scheduledFor,
            'executed_at': executedAt,
            'success': resolvedSuccess,
            'duration_ms': runDuration?.inMilliseconds,
            'error': lastError,
          },
        );
      } finally {
        await _releaseLock(conn, id);
      }
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

Future<void> _ensureColumn(
  Connection conn,
  String statement,
) async {
  try {
    await conn.execute(statement);
  } catch (_) {}
}
