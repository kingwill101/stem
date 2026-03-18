import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

import '../../orm_registry.g.dart';
import 'migrations.dart';

Future<DataSource> openEcommerceDataSource({
  required String databasePath,
}) async {
  final dataSource = bootstrapOrm().sqliteFileDataSource(path: databasePath);

  await dataSource.init();

  final driver = dataSource.connection.driver;
  if (driver is! SchemaDriver) {
    throw StateError('Expected a schema driver for SQLite migrations.');
  }
  final schemaDriver = driver as SchemaDriver;

  final ledger = SqlMigrationLedger(driver, tableName: 'orm_migrations');
  await ledger.ensureInitialized();

  final runner = MigrationRunner(
    schemaDriver: schemaDriver,
    ledger: ledger,
    migrations: buildMigrations(),
  );
  await runner.applyAll();

  await driver.executeRaw('PRAGMA journal_mode=WAL;');
  await driver.executeRaw('PRAGMA synchronous=NORMAL;');

  return dataSource;
}
