import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';

import 'database/datasource.dart';
import 'database/migrations.dart';

class PostgresConnections {
  PostgresConnections._(this.dataSource);

  final DataSource dataSource;

  OrmConnection get connection => dataSource.connection;
  QueryContext get context => dataSource.context;

  static Future<PostgresConnections> open({String? connectionString}) async {
    await _runMigrations(connectionString);
    final dataSource = await _openDataSource(connectionString);
    return PostgresConnections._(dataSource);
  }

  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) => connection.transaction(() => action(context));

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
