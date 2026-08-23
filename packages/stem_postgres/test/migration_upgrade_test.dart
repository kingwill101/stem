import 'dart:io';

import 'package:ormed/migrations.dart';
import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/src/database/migrations.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres migration upgrades require STEM_TEST_POSTGRES_URL',
      () {},
      skip: 'Set STEM_TEST_POSTGRES_URL to run migration upgrade tests.',
    );
    return;
  }

  test(
    'upgrades every historical schema prefix to the current registry',
    () async {
      final migrations = buildMigrations();
      final admin = PostgresDriverAdapter.fromUrl(connectionString);

      try {
        for (
          var prefixLength = 1;
          prefixLength < migrations.length;
          prefixLength += 1
        ) {
          final schema =
              'stem_migration_'
              '${DateTime.now().microsecondsSinceEpoch}_$prefixLength';
          await admin.createSchema(schema);
          try {
            final schemaUrl = _withSearchPath(connectionString, schema);
            final oldAdapter = PostgresDriverAdapter.fromUrl(schemaUrl);
            await oldAdapter.setCurrentSchema(schema);
            await _createMigrationLedger(oldAdapter, schema);
            final oldLedger = SqlMigrationLedger(
              oldAdapter,
              tableName: 'orm_migrations',
            );
            final oldRunner = MigrationRunner(
              schemaDriver: oldAdapter,
              ledger: oldLedger,
              migrations: migrations.take(prefixLength).toList(),
              defaultSchema: schema,
              emitEvents: false,
            );
            final oldReport = await oldRunner.applyAll();
            expect(
              oldReport.actions,
              hasLength(prefixLength),
              reason: 'old prefix length $prefixLength',
            );
            await oldAdapter.close();

            final currentAdapter = PostgresDriverAdapter.fromUrl(schemaUrl);
            await currentAdapter.setCurrentSchema(schema);
            final currentLedger = SqlMigrationLedger(
              currentAdapter,
              tableName: 'orm_migrations',
            );
            final currentRunner = MigrationRunner(
              schemaDriver: currentAdapter,
              ledger: currentLedger,
              migrations: migrations,
              defaultSchema: schema,
              emitEvents: false,
            );
            final upgrade = await currentRunner.applyAll();
            expect(
              upgrade.actions,
              hasLength(migrations.length - prefixLength),
              reason: 'prefix length $prefixLength',
            );
            final statuses = await currentRunner.status();
            expect(
              statuses.every((status) => status.applied),
              isTrue,
              reason: 'prefix length $prefixLength',
            );
            await currentAdapter.close();
          } finally {
            await admin.dropSchemaIfExists(schema);
          }
        }
      } finally {
        await admin.close();
      }
    },
  );

  test(
    'current additive schema accepts legacy-shaped lock writes',
    () async {
      final migrations = buildMigrations();
      final admin = PostgresDriverAdapter.fromUrl(connectionString);
      final schema =
          'stem_mixed_version_${DateTime.now().microsecondsSinceEpoch}';
      await admin.createSchema(schema);
      try {
        final schemaUrl = _withSearchPath(connectionString, schema);
        final adapter = PostgresDriverAdapter.fromUrl(schemaUrl);
        await adapter.setCurrentSchema(schema);
        await _createMigrationLedger(adapter, schema);
        final runner = MigrationRunner(
          schemaDriver: adapter,
          ledger: SqlMigrationLedger(adapter, tableName: 'orm_migrations'),
          migrations: migrations,
          defaultSchema: schema,
          emitEvents: false,
        );
        await runner.applyAll();

        final now = DateTime.now().toUtc();
        const namespace = 'legacy-worker';
        const key = 'legacy-lock';
        await adapter.executeRaw(
          '''
INSERT INTO stem_locks (key, namespace, owner, expires_at, created_at)
VALUES (?, ?, ?, ?, ?)
''',
          [
            key,
            namespace,
            'old-worker',
            now.add(const Duration(seconds: 30)),
            now,
          ],
        );

        final dataSource = createDataSource(connectionString: schemaUrl);
        await dataSource.init();
        final dataSourceDriver = dataSource.connection.driver as SchemaDriver;
        await dataSourceDriver.setCurrentSchema(schema);
        final store = await PostgresLockStore.fromDataSource(
          dataSource,
          namespace: namespace,
          runMigrations: false,
        );
        try {
          expect(
            await store.acquire(key, owner: 'new-worker'),
            isNull,
            reason: 'a current worker must respect an old active lock',
          );

          await adapter.executeRaw(
            '''
UPDATE stem_locks
SET expires_at = ?
WHERE key = ? AND namespace = ?
''',
            [now.subtract(const Duration(seconds: 1)), key, namespace],
          );
          final takeover = await store.acquire(key, owner: 'new-worker');
          expect(takeover, isA<FencedLock>());
          expect((takeover! as FencedLock).fencingToken, equals(1));
          await takeover.release();
        } finally {
          await store.close();
          await dataSource.dispose();
        }
        await adapter.close();
      } finally {
        await admin.dropSchemaIfExists(schema);
        await admin.close();
      }
    },
  );
}

String _withSearchPath(String url, String schema) {
  final uri = Uri.parse(url);
  final params = Map<String, String>.from(uri.queryParameters);
  params['options'] = '-c search_path=$schema,public';
  return uri.replace(queryParameters: params).toString();
}

Future<void> _createMigrationLedger(
  PostgresDriverAdapter adapter,
  String schema,
) {
  // The test database may already contain a public orm_migrations table from
  // another package test. Seed the ledger in the isolated historical schema
  // so the upgrade starts from the same ledger shape a released installation
  // would have, rather than falling back through PostgreSQL's search_path.
  return adapter.executeRaw('''
CREATE TABLE "$schema"."orm_migrations" (
  "id" TEXT PRIMARY KEY,
  "checksum" TEXT NOT NULL,
  "applied_at" TIMESTAMPTZ NOT NULL,
  "batch" INTEGER NOT NULL
)
''');
}
