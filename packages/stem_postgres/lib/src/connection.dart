import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';

import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/src/database/migrations.dart';

/// Holds an active Postgres data source and query helpers.
class PostgresConnections {
  /// Wraps an existing data source without running migrations.
  ///
  /// The caller remains responsible for disposing [dataSource].
  factory PostgresConnections.fromDataSource(DataSource dataSource) =>
      PostgresConnections._(dataSource, ownsDataSource: false);

  /// Creates a connection wrapper for an initialized data source.
  PostgresConnections._(
    DataSource dataSource, {
    required bool ownsDataSource,
    String? connectionString,
  }) : _dataSource = dataSource,
       _ownsDataSource = ownsDataSource,
       _connectionString = connectionString,
       _transactionQueueRef = _queuesByDataSource[dataSource] ??=
           _TransactionQueue();

  static final Expando<_TransactionQueue> _queuesByDataSource =
      Expando<_TransactionQueue>();

  /// Wraps an existing data source and runs migrations before use.
  ///
  /// The caller remains responsible for disposing [dataSource].
  static Future<PostgresConnections> openWithDataSource(
    DataSource dataSource, {
    bool runMigrations = true,
  }) async {
    await dataSource.init();
    if (runMigrations) {
      await _runMigrationsForDataSource(dataSource);
    }
    return PostgresConnections._(dataSource, ownsDataSource: false);
  }

  /// Underlying data source instance.
  DataSource _dataSource;
  final String? _connectionString;
  final bool _ownsDataSource;
  _TransactionQueue _transactionQueueRef;

  /// Convenience accessor for the raw ORM connection.
  OrmConnection get connection => _dataSource.connection;

  /// Convenience accessor for the query context.
  QueryContext get context => _dataSource.context;

  /// Underlying data source instance.
  DataSource get dataSource => _dataSource;

  /// Opens a data source and applies migrations before use.
  static Future<PostgresConnections> open({String? connectionString}) async {
    final dataSource = await _openDataSource(connectionString);
    await _runMigrationsForDataSource(dataSource);
    return PostgresConnections._(
      dataSource,
      ownsDataSource: true,
      connectionString: connectionString,
    );
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) async {
    Future<T> run() async {
      await ensureReady();
      try {
        return await connection.transaction(() => action(context));
      } on Exception catch (error) {
        final message = error.toString();
        if (_ownsDataSource &&
            (message.contains('already been closed') ||
                message.contains('not been initialized'))) {
          await ensureReady(forceReopen: true);
          return connection.transaction(() => action(context));
        }
        rethrow;
      }
    }

    final result = _transactionQueueRef.tail.then((_) => run());
    _transactionQueueRef.tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Ensures the underlying data source is ready for use.
  Future<void> ensureReady({bool forceReopen = false}) async {
    if (forceReopen && _ownsDataSource) {
      await _reopen();
      return;
    }
    if (_dataSource.isInitialized) return;
    try {
      await _dataSource.init();
    } on Exception catch (error) {
      final message = error.toString();
      if (_ownsDataSource &&
          (message.contains('already been closed') ||
              message.contains('not been initialized'))) {
        await _reopen();
        return;
      }
      rethrow;
    }
  }

  /// Closes the data source.
  Future<void> close() async {
    if (_ownsDataSource) {
      await _dataSource.dispose();
    }
  }
}

Future<void> _disposeQuietly(DataSource dataSource) async {
  try {
    await dataSource.dispose();
  } on Object catch (_) {}
}

Future<DataSource> _openDataSource(String? connectionString) async {
  final dataSource = createDataSource(connectionString: connectionString);
  await dataSource.init();
  return dataSource;
}

Future<void> _runMigrationsForDataSource(DataSource dataSource) async {
  ensurePostgresDriverRegistration();
  final driver = dataSource.connection.driver;
  if (driver is! SchemaDriver) {
    throw StateError('Expected a SchemaDriver for Postgres migrations.');
  }
  final schemaDriver = driver as SchemaDriver;

  final schema = dataSource.options.defaultSchema;
  if (schema != null && schema.isNotEmpty) {
    await schemaDriver.setCurrentSchema(schema);
  }

  final ledger = SqlMigrationLedger(driver, tableName: 'orm_migrations');
  await ledger.ensureInitialized();

  final runner = MigrationRunner(
    schemaDriver: schemaDriver,
    ledger: ledger,
    migrations: buildMigrations(),
    defaultSchema: schema,
  );
  await runner.applyAll();
}

extension on PostgresConnections {
  Future<void> _reopen() async {
    final connectionString = _connectionString;
    if (connectionString == null || connectionString.isEmpty) {
      throw StateError('DataSource is closed and cannot be reopened.');
    }
    await _disposeQuietly(_dataSource);
    _dataSource = await _openDataSource(connectionString);
    _transactionQueueRef =
        PostgresConnections._queuesByDataSource[_dataSource] ??=
            _TransactionQueue();
    await _runMigrationsForDataSource(_dataSource);
  }
}

class _TransactionQueue {
  Future<void> tail = Future.value();
}
