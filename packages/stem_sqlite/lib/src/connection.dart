import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

import 'package:stem_sqlite/orm_registry.g.dart';
import 'package:stem_sqlite/src/database/migrations.dart';

/// Holds an active SQLite data source and query helpers.
class SqliteConnections {
  /// Creates a connection wrapper for an initialized data source.
  SqliteConnections._(this.dataSource);

  /// Underlying data source instance.
  final DataSource dataSource;

  /// Convenience accessor for the raw ORM connection.
  OrmConnection get connection => dataSource.connection;

  /// Convenience accessor for the query context.
  QueryContext get context => dataSource.context;

  /// Opens a data source for the provided SQLite [file].
  static Future<SqliteConnections> open(
    File file, {
    bool readOnly = false,
  }) async {
    return _withFileLock(file, () async {
      if (!readOnly) {
        await _runMigrations(file);
      }
      final dataSource = await _openDataSource(file, readOnly: readOnly);
      return SqliteConnections._(dataSource);
    });
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) async {
    if (!dataSource.isInitialized) {
      await dataSource.init();
    }
    return dataSource.connection.transaction(() => action(dataSource.context));
  }

  /// Closes the data source.
  Future<void> close() => dataSource.dispose();
}

Future<DataSource> _openDataSource(File file, {required bool readOnly}) async {
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }

  ensureSqliteDriverRegistration();
  final driver = SqliteDriverAdapter.file(file.path);
  final registry = buildOrmRegistry();
  final dataSource = DataSource(
    DataSourceOptions(driver: driver, registry: registry, database: file.path),
  );
  await dataSource.init();
  if (!readOnly) {
    await driver.executeRaw('PRAGMA journal_mode=WAL;');
    await driver.executeRaw('PRAGMA synchronous=NORMAL;');
  }
  return dataSource;
}

Future<void> _runMigrations(File file) async {
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }

  ensureSqliteDriverRegistration();
  final adapter = SqliteDriverAdapter.file(file.path);
  try {
    final ledger = SqlMigrationLedger(adapter, tableName: 'orm_migrations');
    await ledger.ensureInitialized();

    final runner = MigrationRunner(
      schemaDriver: adapter,
      ledger: ledger,
      migrations: buildMigrations(),
    );
    await runner.applyAll();
  } finally {
    await adapter.close();
  }
}

Future<T> _withFileLock<T>(File file, Future<T> Function() action) async {
  final lockFile = File('${file.path}.lock');
  if (!lockFile.parent.existsSync()) {
    lockFile.parent.createSync(recursive: true);
  }
  final handle = await lockFile.open(mode: FileMode.append);
  try {
    await _acquireLock(handle);
    return await action();
  } finally {
    try {
      await handle.unlock();
    } finally {
      await handle.close();
    }
  }
}

Future<void> _acquireLock(RandomAccessFile handle) async {
  const retryDelay = Duration(milliseconds: 50);
  const maxAttempts = 200;
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      await handle.lock();
      return;
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 11 || code == 35) {
        await Future<void>.delayed(retryDelay);
        continue;
      }
      rethrow;
    }
  }
  throw FileSystemException(
    'lock failed after ${retryDelay.inMilliseconds * maxAttempts}ms',
    handle.path,
  );
}
