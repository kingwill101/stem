import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

import '../../support/postgres_test_harness.dart';

Future<void> main() async {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres lock store contract requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres lock store contract '
          'tests.',
    );
    return;
  }

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres lock store', (dataSource) {
    runLockStoreContractTests(
      adapterName: 'Postgres',
      factory: LockStoreContractFactory(
        create: () async => PostgresLockStore.fromDataSource(
          dataSource,
          namespace: 'stem_lock_contract',
          runMigrations: false,
        ),
        dispose: (store) => (store as PostgresLockStore).close(),
      ),
      settings: const LockStoreContractSettings(
        initialTtl: Duration(seconds: 1),
        expiryBackoff: Duration(seconds: 1),
      ),
    );

    test('lock acquisitions expose increasing fencing tokens', () async {
      final store = await PostgresLockStore.fromDataSource(
        dataSource,
        namespace: 'stem_lock_fencing',
        runMigrations: false,
      );
      final first = await store.acquire('fenced', owner: 'first');
      expect(first, isA<FencedLock>());
      final firstToken = (first! as FencedLock).fencingToken;
      await first.release();

      final second = await store.acquire('fenced', owner: 'second');
      expect(second, isA<FencedLock>());
      expect((second! as FencedLock).fencingToken, greaterThan(firstToken));
      await second.release();
      await store.close();
    });
  }, config: harness.config);
}
