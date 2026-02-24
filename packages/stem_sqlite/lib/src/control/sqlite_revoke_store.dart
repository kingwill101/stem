import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import 'package:stem_sqlite/src/connection.dart';
import 'package:stem_sqlite/src/models/models.dart';

/// SQLite-backed implementation of [RevokeStore].
class SqliteRevokeStore implements RevokeStore {
  SqliteRevokeStore._(this._connections, {required this.namespace});

  /// Creates a revoke store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<SqliteRevokeStore> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.openWithDataSource(dataSource);
    return SqliteRevokeStore._(connections, namespace: resolvedNamespace);
  }

  /// Opens a SQLite revoke store from an existing database [file].
  static Future<SqliteRevokeStore> open(
    File file, {
    String namespace = 'stem',
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.open(file);
    return SqliteRevokeStore._(connections, namespace: resolvedNamespace);
  }

  /// Connects to SQLite via a connection string.
  ///
  /// Accepts `sqlite:///path/to/db.sqlite`, `file:///path/to/db.sqlite`, and
  /// direct file paths.
  static Future<SqliteRevokeStore> connect(
    String connectionString, {
    String namespace = 'stem',
  }) async {
    final uri = Uri.parse(connectionString);
    late final File file;
    switch (uri.scheme) {
      case 'sqlite':
        final path = uri.path.isNotEmpty ? uri.path : uri.host;
        if (path.isEmpty) {
          throw StateError(
            'SQLite URL must include a file path '
            '(e.g. sqlite:///tmp/stem.db).',
          );
        }
        file = File(path);
      case 'file':
        file = File(uri.toFilePath());
      case '':
        file = File(connectionString);
      default:
        throw StateError(
          'Unsupported sqlite revoke store scheme: ${uri.scheme}',
        );
    }
    return open(file, namespace: namespace);
  }

  final SqliteConnections _connections;

  /// Namespace used when incoming entries omit namespace.
  final String namespace;

  @override
  Future<void> close() => _connections.close();

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    final rows = await _connections.context
        .query<StemRevokeEntry>()
        .whereEquals('namespace', namespace)
        .orderBy('version')
        .get();
    return rows.map(_toRevokeEntry).toList(growable: false);
  }

  @override
  Future<int> pruneExpired(String namespace, DateTime clock) async {
    return _connections.runInTransaction((txn) async {
      final expired = await txn
          .query<StemRevokeEntry>()
          .whereEquals('namespace', namespace)
          .whereNotNull('expiresAt')
          .where('expiresAt', clock, PredicateOperator.lessThanOrEqual)
          .get();
      if (expired.isEmpty) {
        return 0;
      }

      for (final row in expired) {
        await txn.repository<StemRevokeEntry>().delete(
          StemRevokeEntryPartial(namespace: row.namespace, taskId: row.taskId),
        );
      }
      return expired.length;
    });
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) async {
    if (entries.isEmpty) {
      return const [];
    }
    return _connections.runInTransaction((txn) async {
      final applied = <RevokeEntry>[];
      for (final entry in entries) {
        final targetNamespace = entry.namespace.trim().isEmpty
            ? namespace
            : entry.namespace;
        final existing = await txn
            .query<StemRevokeEntry>()
            .whereEquals('namespace', targetNamespace)
            .whereEquals('taskId', entry.taskId)
            .firstOrNull();

        if (existing == null || entry.version > existing.version) {
          final model = StemRevokeEntry(
            namespace: targetNamespace,
            taskId: entry.taskId,
            version: entry.version,
            issuedAt: entry.issuedAt,
            terminate: entry.terminate ? 1 : 0,
            reason: entry.reason,
            requestedBy: entry.requestedBy,
            expiresAt: entry.expiresAt,
          );
          await txn.repository<StemRevokeEntry>().upsert(
            model,
            uniqueBy: ['namespace', 'taskId'],
          );
          applied.add(
            entry.copyWith(
              namespace: targetNamespace,
            ),
          );
        } else {
          applied.add(_toRevokeEntry(existing));
        }
      }
      return applied;
    });
  }

  RevokeEntry _toRevokeEntry(StemRevokeEntry row) {
    return RevokeEntry(
      namespace: row.namespace,
      taskId: row.taskId,
      version: row.version,
      issuedAt: row.issuedAt,
      terminate: row.terminate == 1,
      reason: row.reason,
      requestedBy: row.requestedBy,
      expiresAt: row.expiresAt,
    );
  }
}
