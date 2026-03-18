import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('stem_sqlite_revoke_store');
    dbFile = File('${tempDir.path}/revoke.db');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  runRevokeStoreContractTests(
    adapterName: 'SQLite',
    factory: RevokeStoreContractFactory(
      create: () async => SqliteRevokeStore.open(dbFile),
      dispose: (store) => store.close(),
    ),
  );

  test('fromDataSource runs migrations', () async {
    ensureSqliteDriverRegistration();
    final dataSource = buildOrmRegistry().sqliteFileDataSource(
      path: dbFile.path,
    );
    final store = await SqliteRevokeStore.fromDataSource(dataSource);
    try {
      final now = DateTime.utc(2026, 2, 24, 12, 30);
      await store.upsertAll([
        RevokeEntry(
          namespace: 'stem',
          taskId: 'from-datasource',
          version: 1,
          issuedAt: now,
        ),
      ]);

      final listed = await store.list('stem');
      expect(listed.map((entry) => entry.taskId), contains('from-datasource'));
    } finally {
      await store.close();
      await dataSource.dispose();
    }
  });

  test('connect supports sqlite urls', () async {
    final store = await SqliteRevokeStore.connect('sqlite://${dbFile.path}');
    try {
      final now = DateTime.utc(2026, 2, 24, 12, 45);
      await store.upsertAll([
        RevokeEntry(
          namespace: 'stem',
          taskId: 'connect-sqlite',
          version: 1,
          issuedAt: now,
        ),
      ]);
      final listed = await store.list('stem');
      expect(listed.map((entry) => entry.taskId), contains('connect-sqlite'));
    } finally {
      await store.close();
    }
  });

  test('adapter resolves revoke store factory', () async {
    const adapter = StemSqliteAdapter();
    final factory = adapter.revokeStoreFactory(
      Uri.parse('sqlite://${dbFile.path}'),
    );
    expect(factory, isNotNull);
    final store = await factory!.create();
    try {
      final now = DateTime.utc(2026, 2, 24, 13);
      await store.upsertAll([
        RevokeEntry(
          namespace: 'stem',
          taskId: 'adapter-revoke',
          version: 1,
          issuedAt: now,
        ),
      ]);
      final listed = await store.list('stem');
      expect(listed.map((entry) => entry.taskId), contains('adapter-revoke'));
    } finally {
      await factory.dispose(store);
    }
  });
}
