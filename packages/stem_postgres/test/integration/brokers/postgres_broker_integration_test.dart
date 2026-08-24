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

  Future<List<PostgresOperationTiming>> exerciseConnection({
    required bool separateConsumerConnection,
  }) async {
    final namespace = 'broker-connect-${DateTime.now().microsecondsSinceEpoch}';
    final queue = 'connect-queue-${DateTime.now().microsecondsSinceEpoch}';
    final timings = <PostgresOperationTiming>[];
    final broker = await PostgresBroker.connect(
      connectionString,
      namespace: namespace,
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(hours: 1),
      separateConsumerConnection: separateConsumerConnection,
      timingListener: timings.add,
    );
    try {
      await broker.publish(
        Envelope(name: 'integration.connect', args: const {}, queue: queue),
      );
      final delivery = await broker
          .consume(RoutingSubscription.singleQueue(queue))
          .first
          .timeout(const Duration(seconds: 10));
      expect(delivery.envelope.name, 'integration.connect');
      await broker.ack(delivery);
    } finally {
      await broker.close();
    }
    return timings;
  }

  test('connect can use an independent consumer connection', () async {
    final timings = await exerciseConnection(
      separateConsumerConnection: true,
    );
    expect(
      timings.map((timing) => timing.component),
      containsAll(['broker', 'broker.consumer']),
    );
    expect(
      timings,
      anyElement(
        predicate<PostgresOperationTiming>(
          (timing) =>
              timing.component == 'broker.consumer' &&
              timing.operation == 'broker.ack',
        ),
      ),
    );
  });

  test('connect shares one connection by default', () async {
    final timings = await exerciseConnection(
      separateConsumerConnection: false,
    );
    expect(timings.map((timing) => timing.component), contains('broker'));
    expect(
      timings.map((timing) => timing.component),
      isNot(contains('broker.consumer')),
    );
  });

  test('connect isolates broadcast consumer operations', () async {
    final namespace =
        'broker-broadcast-${DateTime.now().microsecondsSinceEpoch}';
    final channel = 'broadcast-${DateTime.now().microsecondsSinceEpoch}';
    final timings = <PostgresOperationTiming>[];
    final broker = await PostgresBroker.connect(
      connectionString,
      namespace: namespace,
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(hours: 1),
      separateConsumerConnection: true,
      timingListener: timings.add,
    );
    final stream = broker.consume(
      RoutingSubscription(
        queues: const [],
        broadcastChannels: [channel],
      ),
      consumerName: 'broadcast-consumer',
    );
    try {
      final deliveryFuture = stream.first.timeout(const Duration(seconds: 10));
      await broker.publish(
        Envelope(
          name: 'integration.broadcast',
          args: const {},
          queue: channel,
        ),
        routing: RoutingInfo.broadcast(channel: channel),
      );
      final delivery = await deliveryFuture;
      await broker.ack(delivery);
      expect(
        timings,
        anyElement(
          predicate<PostgresOperationTiming>(
            (timing) =>
                timing.component == 'broker' &&
                timing.operation == 'broker.publish',
          ),
        ),
      );
      expect(
        timings,
        anyElement(
          predicate<PostgresOperationTiming>(
            (timing) =>
                timing.component == 'broker.consumer' &&
                timing.operation == 'broker.broadcast.ack',
          ),
        ),
      );
    } finally {
      await broker.close();
    }
  });

  ormedGroup('postgres broker', (dataSource) {
    runBrokerContractTests(
      adapterName: 'Postgres',
      factory: BrokerContractFactory(
        create: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
          runMigrations: false,
        ),
        dispose: (broker) => (broker as PostgresBroker).close(),
        additionalBrokerFactory: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
          runMigrations: false,
        ),
      ),
      settings: const BrokerContractSettings(
        leaseExtension: Duration(seconds: 1),
        queueSettleDelay: Duration(milliseconds: 250),
        replayDelay: Duration(milliseconds: 250),
        capabilities: BrokerContractCapabilities(
          verifyBroadcastFanout: true,
        ),
      ),
    );

    runQueueEventsContractTests(
      adapterName: 'Postgres',
      factory: QueueEventsContractFactory(
        create: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
          runMigrations: false,
        ),
        dispose: (broker) => (broker as PostgresBroker).close(),
        additionalBrokerFactory: () async => PostgresBroker.fromDataSource(
          dataSource,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 50),
          sweeperInterval: const Duration(milliseconds: 200),
          runMigrations: false,
        ),
        additionalDispose: (broker) => (broker as PostgresBroker).close(),
      ),
    );

    test('namespace isolates queue data', () async {
      final namespaceA = 'broker-ns-a-${DateTime.now().microsecondsSinceEpoch}';
      final namespaceB = 'broker-ns-b-${DateTime.now().microsecondsSinceEpoch}';
      final brokerA = await PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespaceA,
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
        runMigrations: false,
      );
      final brokerB = await PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespaceB,
        defaultVisibilityTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 50),
        sweeperInterval: const Duration(milliseconds: 200),
        runMigrations: false,
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
