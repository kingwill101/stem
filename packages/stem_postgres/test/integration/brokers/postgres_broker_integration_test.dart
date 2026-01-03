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
      'Postgres broker integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres broker integration '
          'tests.',
    );
    return;
  }

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres broker', (dataSource) {
    runBrokerContractTests(
      adapterName: 'Postgres',
      factory: BrokerContractFactory(
        create: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
        ),
        dispose: (broker) => (broker as PostgresBroker).close(),
        additionalBrokerFactory: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
        ),
      ),
      settings: const BrokerContractSettings(
        leaseExtension: Duration(seconds: 1),
        queueSettleDelay: Duration(milliseconds: 250),
        replayDelay: Duration(milliseconds: 250),
        verifyBroadcastFanout: true,
      ),
    );

    test('namespace isolates queue data', () async {
      final namespaceA = 'broker-ns-a-${DateTime.now().microsecondsSinceEpoch}';
      final namespaceB = 'broker-ns-b-${DateTime.now().microsecondsSinceEpoch}';
      final brokerA = PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespaceA,
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
      );
      final brokerB = PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespaceB,
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
      );

      try {
        final queue = 'queue-${DateTime.now().microsecondsSinceEpoch}';
        final envelope = Envelope(
          name: 'integration.namespace',
          args: const {'value': 1},
          queue: queue,
        );
        await brokerA.publish(envelope);

        final pendingA = await brokerA.pendingCount(queue);
        final pendingB = await brokerB.pendingCount(queue);

        expect(pendingA, 1);
        expect(pendingB, 0);
      } finally {
        await brokerA.close();
        await brokerB.close();
      }
    });
  }, config: harness.config);

  // CLI health check test removed due to dependency signature changes.
}
