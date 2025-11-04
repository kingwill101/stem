import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart' show PostgresClient;
import 'package:uuid/uuid.dart';

/// PostgreSQL-backed [WorkflowStore] implementation.
class PostgresWorkflowStore implements WorkflowStore {
  PostgresWorkflowStore._(
    this._client, {
    required this.schema,
    required this.namespace,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final PostgresClient _client;
  final String schema;
  final String namespace;
  final Uuid _uuid;

  String get _tablePrefix => namespace.isNotEmpty ? '${namespace}_' : '';

  String get _runsTable => '$schema.${_tablePrefix}workflow_runs';
  String get _stepsTable => '$schema.${_tablePrefix}workflow_steps';
  String get _resumeIndex => '${_tablePrefix}workflow_runs_resume_idx';
  String get _topicIndex => '${_tablePrefix}workflow_runs_topic_idx';

  /// Connects to a PostgreSQL database and ensures the workflow tables exist.
  static Future<PostgresWorkflowStore> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    String? applicationName,
    TlsConfig? tls,
    Uuid? uuid,
  }) async {
    final client = PostgresClient(
      uri,
      applicationName: applicationName,
      tls: tls,
    );
    final store = PostgresWorkflowStore._(
      client,
      schema: schema,
      namespace: namespace,
      uuid: uuid,
    );
    await store._initialize();
    return store;
  }

  Future<void> _initialize() async {
    await _client.run((Connection conn) async {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $_runsTable (
          id TEXT PRIMARY KEY,
          workflow TEXT NOT NULL,
          status TEXT NOT NULL,
          params JSONB NOT NULL,
          result JSONB,
          wait_topic TEXT,
          resume_at TIMESTAMPTZ,
          last_error JSONB,
          suspension_data JSONB,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $_stepsTable (
          run_id TEXT NOT NULL REFERENCES $_runsTable(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          value JSONB,
          position BIGSERIAL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          PRIMARY KEY (run_id, name)
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS $_resumeIndex
        ON $_runsTable(resume_at)
        WHERE resume_at IS NOT NULL
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS $_topicIndex
        ON $_runsTable(wait_topic)
        WHERE wait_topic IS NOT NULL
      ''');
    });
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
  }) async {
    final id = _uuid.v7();
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          INSERT INTO $_runsTable (id, workflow, status, params)
          VALUES (@id, @workflow, @status, @params::jsonb)
        '''),
        parameters: {
          'id': id,
          'workflow': workflow,
          'status': WorkflowStatus.running.name,
          'params': jsonEncode(params),
        },
      );
    });
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named('''
          SELECT id, workflow, status, params, result, wait_topic,
                 resume_at, last_error, suspension_data
          FROM $_runsTable
          WHERE id = @id
        '''),
        parameters: {'id': runId},
      );
      if (result.isEmpty) return null;
      final row = result.first;
      final cursorResult = await conn.execute(
        Sql.named('''
          SELECT COUNT(*) FROM $_stepsTable
          WHERE run_id = @id
        '''),
        parameters: {'id': runId},
      );
      final cursor = (cursorResult.first.first as int?) ?? 0;
      return RunState(
        id: row[0] as String,
        workflow: row[1] as String,
        status: WorkflowStatus.values.firstWhere(
          (value) => value.name == row[2],
          orElse: () => WorkflowStatus.running,
        ),
        cursor: cursor,
        params: _decodeMap(row[3]),
        result: _decodeValue(row[4]),
        waitTopic: row[5] as String?,
        resumeAt: row[6] as DateTime?,
        lastError: _decodeMap(row[7]),
        suspensionData: _decodeMap(row[8]),
      );
    });
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named('''
          SELECT value
          FROM $_stepsTable
          WHERE run_id = @runId AND name = @name
        '''),
        parameters: {'runId': runId, 'name': stepName},
      );
      if (result.isEmpty) return null;
      return _decodeValue(result.first.first) as T?;
    });
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          INSERT INTO $_stepsTable (run_id, name, value)
          VALUES (@runId, @name, @value::jsonb)
          ON CONFLICT (run_id, name) DO NOTHING
        '''),
        parameters: {
          'runId': runId,
          'name': stepName,
          'value': jsonEncode(value),
        },
      );
    });
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 resume_at = @resumeAt,
                 wait_topic = NULL,
                 suspension_data = COALESCE(@data::jsonb, suspension_data),
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {
          'status': WorkflowStatus.suspended.name,
          'resumeAt': when,
          'data': data != null ? jsonEncode(data) : null,
          'id': runId,
        },
      );
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
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 wait_topic = @topic,
                 resume_at = @deadline,
                 suspension_data = @data::jsonb,
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {
          'status': WorkflowStatus.suspended.name,
          'topic': topic,
          'deadline': deadline,
          'data': data != null ? jsonEncode(data) : null,
          'id': runId,
        },
      );
    });
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 resume_at = NULL,
                 wait_topic = NULL,
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {'status': WorkflowStatus.running.name, 'id': runId},
      );
    });
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 result = @result::jsonb,
                 resume_at = NULL,
                 wait_topic = NULL,
                 suspension_data = NULL,
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {
          'status': WorkflowStatus.completed.name,
          'result': result != null ? jsonEncode(result) : null,
          'id': runId,
        },
      );
    });
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 last_error = @error::jsonb,
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {
          'status':
              (terminal ? WorkflowStatus.failed : WorkflowStatus.running).name,
          'error': jsonEncode({
            'error': error.toString(),
            'stack': stack.toString(),
          }),
          'id': runId,
        },
      );
    });
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 resume_at = NULL,
                 wait_topic = NULL,
                 suspension_data =
                     COALESCE(@data::jsonb, suspension_data),
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {
          'status': WorkflowStatus.running.name,
          'data': data != null ? jsonEncode(data) : null,
          'id': runId,
        },
      );
    });
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    return _client.run((Connection conn) async {
      await conn.execute('BEGIN');
      try {
        final selected = await conn.execute(
          Sql.named('''
            SELECT id
              FROM $_runsTable
             WHERE resume_at IS NOT NULL
               AND resume_at <= @now
               AND status = @status
             ORDER BY resume_at ASC
             LIMIT @limit
             FOR UPDATE SKIP LOCKED
          '''),
          parameters: {
            'now': now,
            'status': WorkflowStatus.suspended.name,
            'limit': limit,
          },
        );

        final ids = selected
            .map((row) => row.first as String)
            .toList(growable: false);

        if (ids.isNotEmpty) {
          await conn.execute(
            Sql.named('''
              UPDATE $_runsTable
                 SET resume_at = NULL,
                     updated_at = NOW()
               WHERE id = ANY(@ids)
            '''),
            parameters: {'ids': ids},
          );
        }

        await conn.execute('COMMIT');
        return ids;
      } catch (error) {
        await conn.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named('''
          SELECT id
            FROM $_runsTable
           WHERE wait_topic = @topic
           LIMIT @limit
        '''),
        parameters: {'topic': topic, 'limit': limit},
      );
      return result.map((row) => row.first as String).toList(growable: false);
    });
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    await _client.run((Connection conn) async {
      await conn.execute(
        Sql.named('''
          UPDATE $_runsTable
             SET status = @status,
                 resume_at = NULL,
                 wait_topic = NULL,
                 suspension_data = NULL,
                 updated_at = NOW()
           WHERE id = @id
        '''),
        parameters: {'status': WorkflowStatus.cancelled.name, 'id': runId},
      );
    });
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    await _client.run((Connection conn) async {
      await conn.execute('BEGIN');
      try {
        final target = await conn.execute(
          Sql.named('''
            SELECT position
              FROM $_stepsTable
             WHERE run_id = @runId AND name = @name
            LIMIT 1
          '''),
          parameters: {'runId': runId, 'name': stepName},
        );

        if (target.isEmpty) {
          await conn.execute('ROLLBACK');
          return;
        }

        final position = target.first.first as int;

        await conn.execute(
          Sql.named('''
            DELETE FROM $_stepsTable
             WHERE run_id = @runId
               AND position >= @position
          '''),
          parameters: {'runId': runId, 'position': position},
        );

        await conn.execute('COMMIT');
      } catch (error) {
        await conn.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
  }) async {
    return _client.run((Connection conn) async {
      final conditions = <String>[];
      final parameters = <String, Object?>{'limit': limit};
      if (workflow != null) {
        conditions.add('workflow = @workflow');
        parameters['workflow'] = workflow;
      }
      if (status != null) {
        conditions.add('status = @status');
        parameters['status'] = status.name;
      }
      final buffer = StringBuffer(
        'SELECT r.id, r.workflow, r.status, r.params, r.result, '
        'r.wait_topic, r.resume_at, r.last_error, r.suspension_data, '
        '(SELECT COUNT(*) FROM $_stepsTable s WHERE s.run_id = r.id) AS cursor '
        'FROM $_runsTable r',
      );
      if (conditions.isNotEmpty) {
        buffer.write(' WHERE ${conditions.join(' AND ')}');
      }
      buffer.write(' ORDER BY r.created_at DESC LIMIT @limit');

      final rows = await conn.execute(
        Sql.named(buffer.toString()),
        parameters: parameters,
      );
      return rows
          .map((row) {
            final statusName = row[2] as String;
            final statusValue = WorkflowStatus.values.firstWhere(
              (value) => value.name == statusName,
              orElse: () => WorkflowStatus.running,
            );
            return RunState(
              id: row[0] as String,
              workflow: row[1] as String,
              status: statusValue,
              cursor: (row[9] as int?) ?? 0,
              params: _decodeMap(row[3]).cast<String, Object?>(),
              result: _decodeValue(row[4]),
              waitTopic: row[5] as String?,
              resumeAt: row[6] as DateTime?,
              lastError: _decodeMap(row[7]).cast<String, Object?>(),
              suspensionData: _decodeMap(row[8]),
            );
          })
          .toList(growable: false);
    });
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        Sql.named('''
          SELECT name, value, position, created_at
            FROM $_stepsTable
           WHERE run_id = @runId
           ORDER BY position ASC
        '''),
        parameters: {'runId': runId},
      );
      final entries = <WorkflowStepEntry>[];
      for (final row in result) {
        final positionValue = row[2];
        final position = positionValue is int
            ? positionValue
            : positionValue is num
            ? positionValue.toInt()
            : entries.length;
        entries.add(
          WorkflowStepEntry(
            name: row[0] as String,
            value: _decodeValue(row[1]),
            position: position,
            completedAt: row[3] as DateTime?,
          ),
        );
      }
      return entries;
    });
  }

  Future<void> close() async {
    await _client.close();
  }

  Map<String, Object?> _decodeMap(dynamic value) {
    if (value == null) return const {};
    if (value is String) {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    }
    if (value is Map) {
      return value.cast<String, Object?>();
    }
    return const {};
  }

  Object? _decodeValue(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return jsonDecode(value);
    }
    return value;
  }
}
