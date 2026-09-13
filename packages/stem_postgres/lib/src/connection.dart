import 'dart:async';

// Public constructor names intentionally initialize private implementation
// fields to preserve the package API.
// ignore_for_file: prefer_initializing_formals

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
    this._dataSource, {
    required bool ownsDataSource,
    this._connectionString,
    this._component = 'postgres',
    this._timingListener,
    this._queryTimingListener,
  }) : _ownsDataSource = ownsDataSource {
    _transactionQueueRef = _queuesByDataSource[_dataSource] ??=
        _TransactionQueue();
  }

  static final Expando<_TransactionQueue> _queuesByDataSource =
      Expando<_TransactionQueue>();
  static final Object _transactionScopeZoneKey = Object();

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
  late _TransactionQueue _transactionQueueRef;

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
  }) {
    final inheritedScope = Zone.current[_transactionScopeZoneKey];
    if (inheritedScope is _TransactionScope &&
        identical(inheritedScope.queue, _transactionQueueRef)) {
      if (!inheritedScope.active) {
        return Future.error(StateError('Transaction scope has already ended.'));
      }
      // The ORM connection cannot safely start a second transaction while its
      // transaction callback is active. Reuse the current callback so all
      // writes remain part of the outer transaction.
      return inheritedScope.admit(() => action(context));
    }

    final listener = _timingListener;
    final queued = listener == null ? null : (Stopwatch()..start());

    Future<T> run() async {
      final queueWait = queued?.elapsed ?? Duration.zero;
      final execution = listener == null ? null : (Stopwatch()..start());
      try {
        await ensureReady();
        final result = await _runAttempt(action);
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
          try {
            await ensureReady(forceReopen: true);
            final result = await _runAttempt(action);
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

  /// Admits an operation to the transaction active in the current zone.
  ///
  /// This is used by transaction-aware adapters (such as the outbox). Unlike
  /// merely checking that a transaction is active, admission makes the
  /// operation part of the transaction lifetime and rollback decision.
  Future<T> admitTransactionOperation<T>(Future<T> Function() operation) {
    final scope = Zone.current[_transactionScopeZoneKey];
    if (scope is! _TransactionScope ||
        !identical(scope.queue, _transactionQueueRef)) {
      return Future.error(StateError('No active transaction scope.'));
    }
    return scope.admit(operation);
  }

  Future<T> _runAttempt<T>(
    Future<T> Function(QueryContext context) action,
  ) {
    return connection.transaction(() async {
      final scope = _TransactionScope(_transactionQueueRef);
      Object? rootError;
      StackTrace? rootStack;
      Object? joinedError;
      StackTrace? joinedStack;
      T? result;
      try {
        result = await Zone.current
            .fork(zoneValues: {_transactionScopeZoneKey: scope})
            .run(() => action(context));
      } on Object catch (error, stackTrace) {
        rootError = error;
        rootStack = stackTrace;
      } finally {
        // The drain belongs inside the driver's transaction callback. This
        // keeps admitted, unawaited work from racing the commit.
        try {
          await scope.drain();
        } on Object catch (error, stackTrace) {
          joinedError = error;
          joinedStack = stackTrace;
        }
      }
      // Preserve the callback's error when both it and admitted work failed.
      final callbackError = rootError;
      if (callbackError != null) {
        Error.throwWithStackTrace(
          callbackError,
          rootStack ?? StackTrace.current,
        );
      }
      final admittedError = joinedError;
      if (admittedError != null) {
        Error.throwWithStackTrace(
          admittedError,
          joinedStack ?? StackTrace.current,
        );
      }
      return result as T;
    });
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

class _TransactionScope {
  _TransactionScope(this.queue);

  final _TransactionQueue queue;
  bool active = true;
  final List<_JoinedOperation<dynamic>> _pending = [];

  Future<T> admit<T>(Future<T> Function() operation) {
    if (!active) {
      return Future.error(StateError('Transaction scope has already ended.'));
    }
    final future = Future<T>.sync(operation);
    final joinedOperation = _JoinedOperation<T>(future);
    _pending.add(joinedOperation);
    unawaited(
      future.then<void>(
        (_) {},
        // Attach an immediate handler so an unawaited admission does not
        // report an unhandled error before the transaction drains it.
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );
    return future;
  }

  Future<void> drain() async {
    // Drain immutable batches. Work admitted by a batch is placed in the
    // next batch, allowing children to admit grandchildren to a fixed point.
    Object? firstError;
    StackTrace? firstStack;
    while (true) {
      final batch = List<_JoinedOperation<dynamic>>.of(_pending);
      _pending.clear();
      if (batch.isEmpty) {
        // This synchronous cutover is deliberately adjacent to the empty
        // check: no late admission can race the driver's commit.
        active = false;
        break;
      }
      await Future.wait<void>(
        batch.map((operation) async {
          try {
            await operation.future;
          } on Object catch (error, stackTrace) {
            firstError ??= error;
            firstStack ??= stackTrace;
          }
        }),
      );
    }
    if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  }
}

class _JoinedOperation<T> {
  _JoinedOperation(this.future);

  final Future<T> future;
}
