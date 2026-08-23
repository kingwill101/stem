import 'dart:convert';
import 'dart:io';

import 'package:ormed/migrations.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/database/migrations.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  test(
    'upgrades every historical schema prefix to the current registry',
    () async {
      final migrations = buildMigrations();

      for (
        var prefixLength = 1;
        prefixLength < migrations.length;
        prefixLength += 1
      ) {
        final directory = await Directory.systemTemp.createTemp(
          'stem-sqlite-migration-upgrade-',
        );
        final file = File('${directory.path}/stem.db');
        try {
          final oldAdapter = SqliteDriverAdapter.file(file.path);
          final oldLedger = SqlMigrationLedger(
            oldAdapter,
            tableName: 'orm_migrations',
          );
          final oldRunner = MigrationRunner(
            schemaDriver: oldAdapter,
            ledger: oldLedger,
            migrations: migrations.take(prefixLength).toList(),
            emitEvents: false,
          );
          final oldReport = await oldRunner.applyAll();
          expect(oldReport.actions, hasLength(prefixLength));
          await oldAdapter.close();

          final currentAdapter = SqliteDriverAdapter.file(file.path);
          final currentLedger = SqlMigrationLedger(
            currentAdapter,
            tableName: 'orm_migrations',
          );
          final currentRunner = MigrationRunner(
            schemaDriver: currentAdapter,
            ledger: currentLedger,
            migrations: migrations,
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
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test('current additive schema accepts legacy-shaped queue writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stem-sqlite-mixed-version-',
    );
    final file = File('${directory.path}/stem.db');
    try {
      final adapter = SqliteDriverAdapter.file(file.path);
      final runner = MigrationRunner(
        schemaDriver: adapter,
        ledger: SqlMigrationLedger(adapter, tableName: 'orm_migrations'),
        migrations: buildMigrations(),
        emitEvents: false,
      );
      await runner.applyAll();

      final now = DateTime.now().toUtc();
      await adapter.executeRaw(
        '''
INSERT INTO stem_queue_jobs
  (id, queue, envelope, attempt, max_retries, priority, not_before,
   locked_at, locked_until, locked_by, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          'legacy-queue-job',
          'default',
          jsonEncode({'name': 'legacy.task', 'args': <String, Object?>{}}),
          0,
          0,
          0,
          null,
          null,
          null,
          null,
          now,
          now,
        ],
      );
      final rows = await adapter.queryRaw(
        'SELECT namespace FROM stem_queue_jobs WHERE id = ?',
        ['legacy-queue-job'],
      );
      expect(rows.single['namespace'], equals('stem'));
      await adapter.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'current broker consumes a queue row written before namespace migration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'stem-sqlite-mixed-worker-',
      );
      final file = File('${directory.path}/stem.db');
      try {
        final migrations = buildMigrations();
        final oldAdapter = SqliteDriverAdapter.file(file.path);
        final oldRunner = MigrationRunner(
          schemaDriver: oldAdapter,
          ledger: SqlMigrationLedger(oldAdapter, tableName: 'orm_migrations'),
          migrations: migrations.take(1).toList(),
          emitEvents: false,
        );
        await oldRunner.applyAll();
        final now = DateTime.now().toUtc();
        await oldAdapter.executeRaw(
          '''
INSERT INTO stem_queue_jobs
  (id, queue, envelope, attempt, max_retries, priority, not_before,
   locked_at, locked_until, locked_by, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
          [
            'legacy-before-namespace',
            'default',
            jsonEncode({'name': 'legacy.task', 'args': <String, Object?>{}}),
            0,
            0,
            0,
            null,
            null,
            null,
            null,
            now,
            now,
          ],
        );
        await oldAdapter.close();

        final broker = await SqliteBroker.open(
          file,
          pollInterval: const Duration(milliseconds: 5),
        );
        try {
          final delivery = await broker
              .consume(
                RoutingSubscription.singleQueue('default'),
                consumerName: 'current-worker',
              )
              .first
              .timeout(const Duration(seconds: 2));
          expect(delivery.envelope.name, equals('legacy.task'));
          await broker.ack(delivery);
        } finally {
          await broker.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
