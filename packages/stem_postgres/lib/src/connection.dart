import 'package:ormed/ormed.dart';

import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/src/database/migrations.dart';
import 'package:stem_postgres/src/database/postgres_migration_lock.dart';
import 'package:stem_postgres/src/observability/postgres_timing.dart';

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
    String component = 'postgres',
    PostgresTimingListener? timingListener,
    PostgresQueryTimingListener? queryTimingListener,
  }) : _dataSource = dataSource,
       _ownsDataSource = ownsDataSource,
       _connectionString = connectionString,
       _component = component,
       _timingListener = timingListener,
       _queryTimingListener = queryTimingListener,
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
    String component = 'postgres',
    PostgresTimingListener? timingListener,
    PostgresQueryTimingListener? queryTimingListener,
  }) async {
    await dataSource.init();
    if (runMigrations) {
      await _runMigrationsForDataSource(dataSource);
    }
    final connections = PostgresConnections._(
      dataSource,
      ownsDataSource: false,
      component: component,
      timingListener: timingListener,
      queryTimingListener: queryTimingListener,
    ).._attachQueryListener();
    return connections;
  }

  /// Underlying data source instance.
  DataSource _dataSource;
  final String? _connectionString;
  final bool _ownsDataSource;
  final String _component;
  final PostgresTimingListener? _timingListener;
  final PostgresQueryTimingListener? _queryTimingListener;
  void Function()? _removeQueryListener;
  _TransactionQueue _transactionQueueRef;

  /// Convenience accessor for the raw ORM connection.
  OrmConnection get connection => _dataSource.connection;

  /// Convenience accessor for the query context.
  QueryContext get context => _dataSource.context;

  /// Underlying data source instance.
  DataSource get dataSource => _dataSource;

  /// Opens a data source and applies migrations before use.
  static Future<PostgresConnections> open({
    String? connectionString,
    String component = 'postgres',
    PostgresTimingListener? timingListener,
    PostgresQueryTimingListener? queryTimingListener,
  }) async {
    final dataSource = await _openDataSource(connectionString);
    await _runMigrationsForDataSource(dataSource);
    final connections = PostgresConnections._(
      dataSource,
      ownsDataSource: true,
      connectionString: connectionString,
      component: component,
      timingListener: timingListener,
      queryTimingListener: queryTimingListener,
    ).._attachQueryListener();
    return connections;
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action, {
    String operation = 'transaction',
  }) async {
    final listener = _timingListener;
    final queued = listener == null ? null : (Stopwatch()..start());

    Future<T> run() async {
      final queueWait = queued?.elapsed ?? Duration.zero;
      final execution = listener == null ? null : (Stopwatch()..start());
      try {
        await ensureReady();
        final result = await connection.transaction(() => action(context));
        _notifyTiming(
          operation: operation,
          queueWait: queueWait,
          execution: execution?.elapsed ?? Duration.zero,
          total: queued?.elapsed ?? Duration.zero,
          succeeded: true,
        );
        return result;
      } on Object catch (error) {
        final message = error.toString();
        if (_ownsDataSource &&
            (message.contains('already been closed') ||
                message.contains('not been initialized'))) {
          await ensureReady(forceReopen: true);
          try {
            final result = await connection.transaction(() => action(context));
            _notifyTiming(
              operation: operation,
              queueWait: queueWait,
              execution: execution?.elapsed ?? Duration.zero,
              total: queued?.elapsed ?? Duration.zero,
              succeeded: true,
            );
            return result;
          } on Object catch (retryError) {
            _notifyTiming(
              operation: operation,
              queueWait: queueWait,
              execution: execution?.elapsed ?? Duration.zero,
              total: queued?.elapsed ?? Duration.zero,
              succeeded: false,
              error: retryError.toString(),
            );
            rethrow;
          }
        }
        _notifyTiming(
          operation: operation,
          queueWait: queueWait,
          execution: execution?.elapsed ?? Duration.zero,
          total: queued?.elapsed ?? Duration.zero,
          succeeded: false,
          error: error.toString(),
        );
        rethrow;
      }
    }

    final result = _transactionQueueRef.tail.then((_) => run());
    _transactionQueueRef.tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _notifyTiming({
    required String operation,
    required Duration queueWait,
    required Duration execution,
    required Duration total,
    required bool succeeded,
    String? error,
  }) {
    final listener = _timingListener;
    if (listener == null) return;
    try {
      listener(
        PostgresOperationTiming(
          component: _component,
          operation: operation,
          queueWait: queueWait,
          execution: execution,
          total: total,
          succeeded: succeeded,
          error: error,
        ),
      );
    } on Object {
      // Instrumentation must never change database behavior.
    }
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
    _removeQueryListener?.call();
    _removeQueryListener = null;
    if (!_ownsDataSource) return;

    // DataSource.dispose() unregisters the global ORM entry. If that entry's
    // singleton has not been materialized, Ormed can remove the registration
    // without invoking the driver's close hook. Keep an explicit driver
    // reference so an owned PostgreSQL socket is always closed.
    final driver = _dataSource.isInitialized
        ? _dataSource.connection.driver
        : null;
    try {
      await _dataSource.dispose();
    } finally {
      await driver?.close();
    }
  }

  void _attachQueryListener() {
    final listener = _queryTimingListener;
    if (listener == null) return;
    _removeQueryListener?.call();
    _removeQueryListener = _dataSource.listen((event) {
      try {
        listener(
          PostgresQueryTiming(
            component: _component,
            sql: event.sql,
            duration: Duration(microseconds: (event.time * 1000).round()),
            rowCount: event.rowCount,
            succeeded: event.succeeded,
            error: event.error?.toString(),
          ),
        );
      } on Object {
        // Instrumentation must never change database behavior.
      }
    });
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
  final driver = dataSource.connection.driver;
  if (driver is! SchemaDriver) {
    throw StateError('Expected a SchemaDriver for Postgres migrations.');
  }
  final schemaDriver = driver as SchemaDriver;

  final schema = dataSource.options.defaultSchema;
  if (schema != null && schema.isNotEmpty) {
    await schemaDriver.setCurrentSchema(schema);
  }

  await withPostgresMigrationLock(driver, () async {
    final ledger = SqlMigrationLedger(driver, tableName: 'orm_migrations');
    await ledger.ensureInitialized();

    final runner = MigrationRunner(
      schemaDriver: schemaDriver,
      ledger: ledger,
      migrations: buildMigrations(),
      defaultSchema: schema,
    );
    await runner.applyAll();
  });
}

extension on PostgresConnections {
  Future<void> _reopen() async {
    final connectionString = _connectionString;
    if (connectionString == null || connectionString.isEmpty) {
      throw StateError('DataSource is closed and cannot be reopened.');
    }
    _removeQueryListener?.call();
    _removeQueryListener = null;
    await _disposeQuietly(_dataSource);
    _dataSource = await _openDataSource(connectionString);
    _transactionQueueRef =
        PostgresConnections._queuesByDataSource[_dataSource] ??=
            _TransactionQueue();
    await _runMigrationsForDataSource(_dataSource);
    _attachQueryListener();
  }
}

class _TransactionQueue {
  Future<void> tail = Future.value();
}
