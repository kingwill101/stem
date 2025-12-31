import 'dart:io';

import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
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

  runLockStoreContractTests(
    adapterName: 'Postgres',
    factory: LockStoreContractFactory(
      create: () async => PostgresLockStore.connect(
        connectionString,
        namespace: 'stem_lock_contract',
        applicationName: 'stem-postgres-lock-contract',
      ),
      dispose: (store) => (store as PostgresLockStore).close(),
    ),
    settings: const LockStoreContractSettings(
      initialTtl: Duration(seconds: 1),
      expiryBackoff: Duration(seconds: 1),
    ),
  );
}
