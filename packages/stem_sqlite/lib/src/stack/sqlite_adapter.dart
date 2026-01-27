import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/workflow/sqlite_factories.dart';

/// Adapter that resolves SQLite-backed factories from a `sqlite://` URL.
class StemSqliteAdapter implements StemStoreAdapter {
  /// Creates a SQLite adapter with optional defaults.
  const StemSqliteAdapter({
    this.defaultVisibilityTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 250),
    this.sweeperInterval = const Duration(seconds: 10),
    this.deadLetterRetention = const Duration(days: 7),
    this.backendDefaultTtl = const Duration(days: 1),
    this.backendGroupDefaultTtl = const Duration(days: 1),
    this.backendHeartbeatTtl = const Duration(minutes: 1),
  });

  /// Default visibility timeout for the SQLite broker.
  final Duration defaultVisibilityTimeout;

  /// Poll interval for the SQLite broker.
  final Duration pollInterval;

  /// Sweeper cadence for SQLite broker cleanup.
  final Duration sweeperInterval;

  /// Retention for dead-letter entries.
  final Duration deadLetterRetention;

  /// Default TTL for task results.
  final Duration backendDefaultTtl;

  /// Default TTL for group results.
  final Duration backendGroupDefaultTtl;

  /// TTL for worker heartbeats stored in the backend.
  final Duration backendHeartbeatTtl;

  @override
  String get name => 'stem_sqlite';

  @override
  bool supports(Uri uri, StemStoreKind kind) {
    return uri.scheme == 'sqlite' || uri.scheme == 'file';
  }

  @override
  StemBrokerFactory? brokerFactory(Uri uri) {
    final file = _fileFromUri(uri);
    return sqliteBrokerFactory(
      file,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    );
  }

  @override
  StemBackendFactory? backendFactory(Uri uri) {
    final file = _fileFromUri(uri);
    return sqliteResultBackendFactory(
      file,
      defaultTtl: backendDefaultTtl,
      groupDefaultTtl: backendGroupDefaultTtl,
      heartbeatTtl: backendHeartbeatTtl,
    );
  }

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) {
    final file = _fileFromUri(uri);
    return sqliteWorkflowStoreFactory(file);
  }

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) => null;

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) => null;

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) => null;
}

File _fileFromUri(Uri uri) {
  if (uri.scheme == 'file') {
    return File.fromUri(uri);
  }
  final path = uri.path.isNotEmpty ? uri.path : uri.host;
  if (path.isEmpty) {
    throw StateError(
      'SQLite URL must include a file path (e.g. sqlite:///tmp/stem.db).',
    );
  }
  return File(path);
}
