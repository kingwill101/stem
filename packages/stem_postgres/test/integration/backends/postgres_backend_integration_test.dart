import 'dart:io';

import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres result backend integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres result backend integration tests.',
    );
    return;
  }

  runResultBackendContractTests(
    adapterName: 'Postgres',
    factory: ResultBackendContractFactory(
      create: () async => PostgresResultBackend.connect(
        connectionString,
        applicationName: 'stem-postgres-backend-test',
        namespace: 'stem',
        defaultTtl: const Duration(seconds: 1),
        groupDefaultTtl: const Duration(seconds: 1),
        heartbeatTtl: const Duration(seconds: 1),
      ),
      dispose: (backend) => (backend as PostgresResultBackend).close(),
    ),
    settings: const ResultBackendContractSettings(
      statusTtl: Duration(seconds: 1),
      groupTtl: Duration(seconds: 1),
      heartbeatTtl: Duration(seconds: 1),
      settleDelay: Duration(milliseconds: 250),
    ),
  );
}
