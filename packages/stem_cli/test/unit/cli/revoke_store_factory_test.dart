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
  });
}
