import 'dart:async';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/workflow_models.dart';

/// PostgreSQL-backed implementation of [RevokeStore].
class PostgresRevokeStore implements RevokeStore {
  PostgresRevokeStore._(this._connections, {required this.namespace});

  final PostgresConnections _connections;

  /// Namespace used to scope revoke entries.
  final String namespace;

  /// Connects to PostgreSQL and returns a revoke store instance.
  static Future<PostgresRevokeStore> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    String? applicationName,
    TlsConfig? tls,
  }) async {
    final resolvedNamespace =
        namespace.trim().isEmpty ? 'stem' : namespace.trim();
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresRevokeStore._(
      connections,
      namespace: resolvedNamespace,
    );
  }

  /// Creates a revoke store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static PostgresRevokeStore fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
  }) {
    final resolvedNamespace =
        namespace.trim().isNotEmpty ? namespace.trim() : 'stem';
    final connections = PostgresConnections.fromDataSource(dataSource);
    return PostgresRevokeStore._(connections, namespace: resolvedNamespace);
  }

  @override
  Future<void> close() async {
    await _connections.close();
  }

  @override
  Future<List<RevokeEntry>> list(String ns) async {
    final ctx = _connections.context;
    final entries = await ctx
        .query<$StemRevokeEntry>()
        .whereEquals('namespace', ns)
        .get();

    return entries
        .map(
          (e) => RevokeEntry(
            namespace: e.namespace,
            taskId: e.taskId,
            terminate: e.terminate,
            reason: e.reason,
            requestedBy: e.requestedBy,
            issuedAt: e.issuedAt,
            expiresAt: e.expiresAt,
            version: e.version,
          ),
        )
        .toList()
      ..sort((a, b) => a.version.compareTo(b.version));
  }

  @override
  Future<int> pruneExpired(String ns, DateTime clock) async {
    return _connections.runInTransaction((ctx) async {
      final expired = await ctx
          .query<$StemRevokeEntry>()
          .whereEquals('namespace', ns)
          .whereNotNull('expiresAt')
          .where('expiresAt', clock, PredicateOperator.lessThanOrEqual)
          .get();

      var count = 0;
      for (final entry in expired) {
        await ctx.repository<$StemRevokeEntry>().delete(entry);
        count++;
      }
      return count;
    });
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) async {
    if (entries.isEmpty) return const [];

    return _connections.runInTransaction((ctx) async {
      final applied = <RevokeEntry>[];

      for (final entry in entries) {
        // Check if entry exists and has a lower version
        final existing = await ctx
            .query<$StemRevokeEntry>()
            .whereEquals('taskId', entry.taskId)
            .whereEquals('namespace', entry.namespace)
            .first();

        final shouldUpdate =
            existing == null || existing.version < entry.version;

        if (shouldUpdate) {
          final model = $StemRevokeEntry(
            taskId: entry.taskId,
            namespace: entry.namespace,
            terminate: entry.terminate,
            reason: entry.reason,
            requestedBy: entry.requestedBy,
            issuedAt: entry.issuedAt,
            expiresAt: entry.expiresAt,
            version: existing != null ? entry.version : entry.version,
            updatedAt: DateTime.now(),
          );

          if (existing != null) {
            await ctx.repository<$StemRevokeEntry>().update(model);
          } else {
            await ctx.repository<$StemRevokeEntry>().insert(model);
          }
        }

        // Return the effective entry (either new or existing)
        applied.add(entry);
      }

      applied.sort((a, b) => a.version.compareTo(b.version));
      return applied;
    });
  }
}
