import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed/migrations.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/src/database/migrations.dart';

/// Test harness wiring Postgres DataSource + ormedGroup isolation.
class StemPostgresTestHarness {
  /// Creates a test harness.
  StemPostgresTestHarness({
    required this.dataSource,
    required this.config,
    required this.connectionString,
  });

  /// Base DataSource shared by the test manager.
  final DataSource dataSource;

  /// ormedGroup configuration for this harness.
  final OrmedTestConfig config;

  /// Connection string used to create adapters.
  final String connectionString;

  /// Disposes the base DataSource.
  Future<void> dispose() async {
    await dataSource.dispose();
  }
}

/// Creates a Postgres test harness configured for ormedGroup isolation.
Future<StemPostgresTestHarness> createStemPostgresTestHarness({
  required String connectionString,
  bool? logging,
}) async {
  ensurePostgresDriverRegistration();

  final enableLogging =
      logging ?? Platform.environment['STEM_TEST_POSTGRES_LOGGING'] == 'true';
  final dataSource = createDataSource(
    connectionString: connectionString,
    logging: enableLogging,
  );
  await dataSource.init();

  final config = setUpOrmed(
    dataSource: dataSource,
    runMigrations: _runTestMigrations,
    strategy: DatabaseIsolationStrategy.migrateWithTransactions,
    adapterFactory: (dbName) {
      final schemaUrl = _withSearchPath(connectionString, dbName);
      return PostgresDriverAdapter.custom(
        config: DatabaseConfig(
          driver: 'postgres',
          options: {'url': schemaUrl},
        ),
      );
    },
  );

  return StemPostgresTestHarness(
    dataSource: dataSource,
    config: config,
    connectionString: connectionString,
  );
}

String _withSearchPath(String url, String schema) {
  final uri = Uri.parse(url);
  final optionsValue = '-c search_path=$schema,public';
  final params = Map<String, String>.from(uri.queryParameters);
  params['options'] = optionsValue;
  return uri.replace(queryParameters: params).toString();
}

Future<void> _runTestMigrations(DataSource dataSource) async {
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
