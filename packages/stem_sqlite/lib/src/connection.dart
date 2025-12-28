import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

import '../orm_registry.g.dart';
import 'database/migrations.dart';

class SqliteConnections {
  SqliteConnections._(this.dataSource);

  final DataSource dataSource;

  OrmConnection get connection => dataSource.connection;
  QueryContext get context => dataSource.context;

  static Future<SqliteConnections> open(
    File file, {
    bool readOnly = false,
  }) async {
    if (!readOnly) {
      await _runMigrations(file);
    }
    final dataSource = await _openDataSource(file, readOnly: readOnly);
    return SqliteConnections._(dataSource);
  }

  Future<T> runInTransaction<T>(
    Future<T> Function(QueryContext context) action,
  ) => connection.transaction(() => action(context));

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
    DataSourceOptions(
      driver: driver,
      registry: registry,
      database: file.path,
    ),
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
    final ledger = SqlMigrationLedger(
      adapter,
      tableName: 'orm_migrations',
    );
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
