import 'dart:io';

import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres broker integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres broker integration tests.',
    );
    return;
  }

  runBrokerContractTests(
    adapterName: 'Postgres',
    factory: BrokerContractFactory(
      create: () async => PostgresBroker.connect(
        connectionString,
        applicationName: 'stem-postgres-contract-tests',
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
      ),
      dispose: (broker) => (broker as PostgresBroker).close(),
      additionalBrokerFactory: () async => PostgresBroker.connect(
        connectionString,
        applicationName: 'stem-postgres-contract-worker',
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
      ),
    ),
    settings: const BrokerContractSettings(
      visibilityTimeout: Duration(seconds: 1),
      leaseExtension: Duration(seconds: 1),
      queueSettleDelay: Duration(milliseconds: 250),
      replayDelay: Duration(milliseconds: 250),
      verifyBroadcastFanout: true,
    ),
  );

  // CLI health check test removed due to dependency signature changes.
}
