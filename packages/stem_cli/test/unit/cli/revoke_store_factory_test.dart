import 'dart:io';

import 'package:stem/stem.dart' hide RevokeStoreFactory;
import 'package:stem_cli/src/cli/revoke_store_factory.dart';
// import 'package:stem_cloud_worker/stem_cloud_worker.dart';
import 'package:test/test.dart';

void main() {
  group('RevokeStoreFactory', () {
    test('supports cloud revoke store URLs', () async {
      final config = StemConfig(
        brokerUrl: 'redis://localhost:6379',
        revokeStoreUrl: 'http://localhost:8080/v1',
      );

      final store = await RevokeStoreFactory.create(
        config: config,
        environment: const {'STEM_CLOUD_ACCESS_TOKEN': 'token'},
      );

      // expect(store, isA<StemCloudRevokeStore>());
      await store.close();
    }, skip: true);

    test('supports sqlite revoke store URLs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'stem_cli_revoke_sqlite',
      );
      final dbPath = '${tempDir.path}/revokes.db';
      final config = StemConfig(
        brokerUrl: 'redis://localhost:6379',
        revokeStoreUrl: 'sqlite://$dbPath',
      );

      final store = await RevokeStoreFactory.create(config: config);
      try {
        expect(store.runtimeType.toString(), contains('SqliteRevokeStore'));
      } finally {
        await store.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('falls back to sqlite result backend URL for revoke store', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'stem_cli_revoke_sqlite_fallback',
      );
      final dbPath = '${tempDir.path}/fallback.db';
      final config = StemConfig(
        brokerUrl: 'redis://localhost:6379',
        resultBackendUrl: 'sqlite://$dbPath',
      );

      final store = await RevokeStoreFactory.create(config: config);
      try {
        expect(store.runtimeType.toString(), contains('SqliteRevokeStore'));
      } finally {
        await store.close();
        await tempDir.delete(recursive: true);
      }
    });
  });
}
