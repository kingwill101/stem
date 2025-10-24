import 'dart:async';

import 'package:postgres/postgres.dart';

import '../postgres/postgres_client.dart';
import '../security/tls.dart';
import 'revoke_store.dart';

/// PostgreSQL-backed implementation of [RevokeStore].
class PostgresRevokeStore implements RevokeStore {
  PostgresRevokeStore._(
    this._client, {
    required this.schema,
    required this.namespace,
  });

  final PostgresClient _client;
  final String schema;
  final String namespace;

  static Future<PostgresRevokeStore> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    String? applicationName,
    TlsConfig? tls,
  }) async {
    final client = PostgresClient(
      uri,
      applicationName: applicationName ?? 'stem-revoke-store',
      tls: tls,
    );
    final store = PostgresRevokeStore._(
      client,
      schema: schema,
      namespace: namespace,
    );
    await store._initialize();
    return store;
  }

  Future<void> _initialize() async {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    await _client.run((Connection conn) async {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}revokes (
          task_id TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          terminate BOOLEAN NOT NULL DEFAULT FALSE,
          reason TEXT,
          requested_by TEXT,
          issued_at TIMESTAMPTZ NOT NULL,
          expires_at TIMESTAMPTZ,
          version BIGINT NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}revokes_namespace_idx
        ON $schema.${prefix}revokes(namespace)
      ''');
    });
  }

  @override
  Future<void> close() async {
    await _client.close();
  }

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    return _client.run((Connection conn) async {
      final results = await conn.execute(
        'SELECT task_id, namespace, terminate, reason, requested_by, '
        'issued_at, expires_at, version '
        'FROM $schema.${this.namespace}_revokes '
        'WHERE namespace = @namespace',
        parameters: {'namespace': namespace},
      );
      return results
          .map(
            (row) => RevokeEntry(
              namespace: row[1] as String,
              taskId: row[0] as String,
              terminate: row[2] as bool,
              reason: row[3] as String?,
              requestedBy: row[4] as String?,
              issuedAt: row[5] as DateTime,
              expiresAt: row[6] as DateTime?,
              version: row[7] as int,
            ),
          )
          .toList()
        ..sort((a, b) => a.version.compareTo(b.version));
    });
  }

  @override
  Future<int> pruneExpired(String namespace, DateTime clock) async {
    return _client.run((Connection conn) async {
      final result = await conn.execute(
        'DELETE FROM $schema.${this.namespace}_revokes '
        'WHERE namespace = @namespace AND expires_at IS NOT NULL '
        'AND expires_at <= @expires RETURNING task_id',
        parameters: {'namespace': namespace, 'expires': clock},
      );
      return result.length;
    });
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) async {
    if (entries.isEmpty) return const [];

    return _client.run((Connection conn) async {
      final applied = <RevokeEntry>[];
      for (final entry in entries) {
        final result = await conn.execute(
          'INSERT INTO $schema.${namespace}_revokes '
          '(task_id, namespace, terminate, reason, requested_by, issued_at, '
          'expires_at, version) '
          'VALUES (@taskId, @namespace, @terminate, @reason, @requestedBy, '
          '@issuedAt, @expiresAt, @version) '
          'ON CONFLICT (task_id) DO UPDATE SET '
          'terminate = CASE WHEN $schema.${namespace}_revokes.version < @version '
          'THEN EXCLUDED.terminate ELSE $schema.${namespace}_revokes.terminate END, '
          'reason = CASE WHEN $schema.${namespace}_revokes.version < @version '
          'THEN EXCLUDED.reason ELSE $schema.${namespace}_revokes.reason END, '
          'requested_by = CASE WHEN $schema.${namespace}_revokes.version < @version '
          'THEN EXCLUDED.requested_by ELSE $schema.${namespace}_revokes.requested_by END, '
          'issued_at = CASE WHEN $schema.${namespace}_revokes.version < @version '
          'THEN EXCLUDED.issued_at ELSE $schema.${namespace}_revokes.issued_at END, '
          'expires_at = CASE WHEN $schema.${namespace}_revokes.version < @version '
          'THEN EXCLUDED.expires_at ELSE $schema.${namespace}_revokes.expires_at END, '
          'version = GREATEST($schema.${namespace}_revokes.version, @version), '
          'updated_at = NOW() '
          'RETURNING task_id, namespace, terminate, reason, requested_by, '
          'issued_at, expires_at, version',
          parameters: {
            'taskId': entry.taskId,
            'namespace': entry.namespace,
            'terminate': entry.terminate,
            'reason': entry.reason,
            'requestedBy': entry.requestedBy,
            'issuedAt': entry.issuedAt,
            'expiresAt': entry.expiresAt,
            'version': entry.version,
          },
        );
        final row = result.first;
        applied.add(
          RevokeEntry(
            namespace: row[1] as String,
            taskId: row[0] as String,
            terminate: row[2] as bool,
            reason: row[3] as String?,
            requestedBy: row[4] as String?,
            issuedAt: row[5] as DateTime,
            expiresAt: row[6] as DateTime?,
            version: row[7] as int,
          ),
        );
      }
      applied.sort((a, b) => a.version.compareTo(b.version));
      return applied;
    });
  }
}
