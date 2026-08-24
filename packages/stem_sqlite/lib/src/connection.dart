import 'dart:async';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

import 'package:stem_sqlite/src/database/migrations.dart';
import 'package:stem_sqlite/src/database/orm_registry.g.dart';

const int _sqliteBusyTimeoutMs = 5000;

/// Holds an active SQLite data source and query helpers.
class SqliteConnections {
  /// Wraps an existing data source without running migrations.
  ///
  /// The caller remains responsible for disposing [dataSource].
  factory SqliteConnections.fromDataSource(DataSource dataSource) =>
      SqliteConnections._(
        dataSource,
        ownsDataSource: false,
        coordinationKey: _databaseCoordinationKey(dataSource),
      );

  /// Creates a connection wrapper for an initialized data source.
  SqliteConnections._(
    this.dataSource, {
    required bool ownsDataSource,
    String? coordinationKey,
  }) : _ownsDataSource = ownsDataSource,
       _coordinationKey = coordinationKey;

  /// Underlying data source instance.
  final DataSource dataSource;
  final bool _ownsDataSource;
  final String? _coordinationKey;

  // The native SQLite driver keeps transaction depth on the connection and
  // uses savepoints for nested transactions. Since transaction callbacks are
  // asynchronous, two callers can otherwise interleave on the same ORM
  // connection and make one caller release or roll back the other's
  // savepoint. Serialize the transaction boundary at the wrapper, where all
  // Stem SQLite stores already converge.
  Future<void> _transactionTail = Future<void>.value();

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
      return SqliteConnections._(
        dataSource,
        ownsDataSource: true,
        coordinationKey: file.absolute.path,
      );
    });
  }

  /// Wraps an existing data source and runs migrations before use.
  ///
  /// The caller remains responsible for disposing [dataSource].
  static Future<SqliteConnections> openWithDataSource(
    DataSource dataSource,
  ) async {
    await _runMigrationsForDataSource(dataSource);
    return SqliteConnections._(
      dataSource,
      ownsDataSource: false,
      coordinationKey: _databaseCoordinationKey(dataSource),
    );
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) async {
    final previous = _transactionTail;
    final release = Completer<void>();
    _transactionTail = release.future;

    await previous;
    try {
      Future<T> transaction() async {
        if (!dataSource.isInitialized) {
          await dataSource.init();
        }
        return dataSource.connection.transaction(
          () => action(dataSource.context),
        );
      }

      final key = _coordinationKey;
      return await (key == null
          ? transaction()
          : _serializeFileTransactionForKey(key, transaction));
    } finally {
      release.complete();
    }
  }

  /// Closes the data source.
  Future<void> close() async {
    await _transactionTail;
    if (_ownsDataSource) {
      await dataSource.dispose();
    }
  }
}

final Map<String, Future<void>> _fileTransactionTails = {};

Future<T> _serializeFileTransactionForKey<T>(
  String key,
  Future<T> Function() action,
) async {
  final previous = _fileTransactionTails[key] ?? Future<void>.value();
  final release = Completer<void>();
  _fileTransactionTails[key] = release.future;
  await previous;
  try {
    return await action();
  } finally {
    release.complete();
    if (identical(_fileTransactionTails[key], release.future)) {
      unawaited(_fileTransactionTails.remove(key));
    }
  }
}

String? _databaseCoordinationKey(DataSource dataSource) {
  final path = dataSource.isInitialized
      ? (dataSource.connection.options['path'] ??
            dataSource.connection.options['database'])
      : dataSource.options.database;
  if (path == null || path == ':memory:') return null;
  return File(path.toString()).absolute.path;
}

Future<DataSource> _openDataSource(File file, {required bool readOnly}) async {
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }

  final dataSource = buildOrmRegistry().sqliteFileDataSource(path: file.path);
  await dataSource.init();
  final driver = dataSource.connection.driver;
  await driver.executeRaw('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs;');
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

  final adapter = SqliteDriverAdapter.file(file.path);
  try {
    await adapter.executeRaw('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs;');
    await adapter.executeRaw('PRAGMA journal_mode=WAL;');
    await adapter.executeRaw('PRAGMA synchronous=NORMAL;');
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

Future<void> _runMigrationsForDataSource(DataSource dataSource) async {
  if (!dataSource.isInitialized) {
    await dataSource.init();
  }
  final driver = dataSource.connection.driver;
  if (driver is! SchemaDriver) {
    throw StateError('Expected a SchemaDriver for SQLite migrations.');
  }
  final schemaDriver = driver as SchemaDriver;
  await driver.executeRaw('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs;');
  await driver.executeRaw('PRAGMA journal_mode=WAL;');
  await driver.executeRaw('PRAGMA synchronous=NORMAL;');

  final ledger = SqlMigrationLedger(driver, tableName: 'orm_migrations');
  await ledger.ensureInitialized();

  final runner = MigrationRunner(
    schemaDriver: schemaDriver,
    ledger: ledger,
    migrations: buildMigrations(),
  );
  await runner.applyAll();
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
