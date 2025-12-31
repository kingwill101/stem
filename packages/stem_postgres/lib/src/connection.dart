import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';

import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/src/database/migrations.dart';

/// Holds an active Postgres data source and query helpers.
class PostgresConnections {
  /// Creates a connection wrapper for an initialized data source.
  PostgresConnections._(this.dataSource);

  /// Underlying data source instance.
  final DataSource dataSource;

  /// Convenience accessor for the raw ORM connection.
  OrmConnection get connection => dataSource.connection;

  /// Convenience accessor for the query context.
  QueryContext get context => dataSource.context;

  /// Opens a data source and applies migrations before use.
  static Future<PostgresConnections> open({String? connectionString}) async {
    await _runMigrations(connectionString);
    final dataSource = await _openDataSource(connectionString);
    return PostgresConnections._(dataSource);
  }

  /// Runs [action] inside a database transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) => connection.transaction(() => action(context));

  /// Closes the data source.
  Future<void> close() => dataSource.dispose();
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
