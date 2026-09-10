import 'dart:convert';
import 'dart:io';

import 'package:ormed/migrations.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/database/migrations.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

const _migrationTestTimeout = Timeout(Duration(minutes: 1));

void main() {
  test('migration adapters use production pragmas on every open', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stem-sqlite-migration-settings-',
    );
    final file = File('${directory.path}/stem.db');
    try {
      // synchronous is connection-local, so configuring only the first
      // adapter is not enough for the historical-prefix upgrade tests.
      for (var open = 0; open < 2; open += 1) {
        final adapter = await _openMigrationAdapter(file);
        try {
          expect(
            (await adapter.queryRaw(
              'PRAGMA journal_mode',
            )).single.values.single,
            'wal',
          );
          expect(
            (await adapter.queryRaw('PRAGMA synchronous')).single.values.single,
            1,
          );
          expect(
            (await adapter.queryRaw(
              'PRAGMA busy_timeout',
            )).single.values.single,
            5000,
          );
        } finally {
          await adapter.close();
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

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
          final oldAdapter = await _openMigrationAdapter(file);
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

          final currentAdapter = await _openMigrationAdapter(file);
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
    timeout: _migrationTestTimeout,
  );

  test(
    'current additive schema accepts legacy-shaped queue writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'stem-sqlite-mixed-version-',
      );
      final file = File('${directory.path}/stem.db');
      try {
        final adapter = await _openMigrationAdapter(file);
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
    },
    timeout: _migrationTestTimeout,
  );

  test(
    'current broker consumes a queue row written before namespace migration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'stem-sqlite-mixed-worker-',
      );
      final file = File('${directory.path}/stem.db');
      try {
        final migrations = buildMigrations();
        final oldAdapter = await _openMigrationAdapter(file);
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
    timeout: _migrationTestTimeout,
  );
}

Future<SqliteDriverAdapter> _openMigrationAdapter(File file) async {
  final adapter = SqliteDriverAdapter.file(file.path);
  try {
    // Match SqliteConnections migration setup. SQLite's default rollback
    // journal with FULL synchronization otherwise fsyncs every schema and
    // ledger write, making these file-backed tests disk-speed dependent.
    await adapter.executeRaw('PRAGMA busy_timeout = 5000;');
    await adapter.executeRaw('PRAGMA journal_mode=WAL;');
    await adapter.executeRaw('PRAGMA synchronous=NORMAL;');
    return adapter;
  } catch (_) {
    await adapter.close();
    rethrow;
  }
}
