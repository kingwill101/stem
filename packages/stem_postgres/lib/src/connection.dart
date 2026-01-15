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
  PostgresConnections._(this.dataSource, {required bool ownsDataSource})
    : _ownsDataSource = ownsDataSource;

  /// Wraps an existing data source and runs migrations before use.
  ///
  /// The caller remains responsible for disposing [dataSource].
  static Future<PostgresConnections> openWithDataSource(
    DataSource dataSource,
  ) async {
    await _runMigrationsForDataSource(dataSource);
    return PostgresConnections._(dataSource, ownsDataSource: false);
  }

  /// Underlying data source instance.
  final DataSource dataSource;
  final bool _ownsDataSource;

  /// Convenience accessor for the raw ORM connection.
  OrmConnection get connection => dataSource.connection;

  /// Convenience accessor for the query context.
  QueryContext get context => dataSource.context;

  /// Opens a data source and applies migrations before use.
  static Future<PostgresConnections> open({String? connectionString}) async {
    await _runMigrations(connectionString);
    final dataSource = await _openDataSource(connectionString);
    return PostgresConnections._(dataSource, ownsDataSource: true);
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) => connection.transaction(() => action(context));

  /// Closes the data source.
  Future<void> close() async {
    if (_ownsDataSource) {
      await dataSource.dispose();
    }
  }
}

Future<DataSource> _openDataSource(String? connectionString) async {
  final dataSource = createDataSource(connectionString: connectionString);
  await dataSource.init();
  return dataSource;
}

Future<void> _runMigrations(String? connectionString) async {
  ensurePostgresDriverRegistration();
  final url = (connectionString != null && connectionString.isNotEmpty)
      ? connectionString
      : () {
          final config = loadOrmConfig();
          final options = config.driver.options as Map<String, dynamic>;
          return options['url'] as String;
        }();
  final adapter = PostgresDriverAdapter.custom(
    config: DatabaseConfig(driver: 'postgres', options: {'url': url}),
  );

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
