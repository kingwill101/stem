import 'dart:async';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('stem_sqlite_broker_test');
    dbFile = File('${tempDir.path}/broker.db');
  });

  tearDown(() async {
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  runBrokerContractTests(
    adapterName: 'SQLite',
    factory: BrokerContractFactory(
      create: () async => SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 25),
        sweeperInterval: const Duration(milliseconds: 75),
      ),
      dispose: (broker) => (broker as SqliteBroker).close(),
      additionalBrokerFactory: () async => SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 25),
        sweeperInterval: const Duration(milliseconds: 75),
      ),
    ),
    settings: const BrokerContractSettings(
      visibilityTimeout: Duration(milliseconds: 300),
      leaseExtension: Duration(milliseconds: 300),
      queueSettleDelay: Duration(milliseconds: 250),
      replayDelay: Duration(milliseconds: 250),
      capabilities: BrokerContractCapabilities(
        verifyBroadcastFanout: true,
      ),
    ),
  );

  test('fromDataSource runs migrations', () async {
    ensureSqliteDriverRegistration();
    final dataSource = DataSource(
      DataSourceOptions(
        driver: SqliteDriverAdapter.file(dbFile.path),
        registry: buildOrmRegistry(),
        database: dbFile.path,
      ),
    );
    final broker = await SqliteBroker.fromDataSource(
      dataSource,
      defaultVisibilityTimeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(milliseconds: 75),
    );
    try {
      final queue = 'queue-${DateTime.now().microsecondsSinceEpoch}';
      final envelope = Envelope(
        name: 'sqlite.datasource',
        args: const {'value': 1},
        queue: queue,
      );
      await broker.publish(envelope);

      final pending = await broker.pendingCount(queue);
      expect(pending, 1);
    } finally {
      await broker.close();
      await dataSource.dispose();
    }
  });

  test('namespace isolates queue data', () async {
    final namespaceA =
        'sqlite-broker-a-${DateTime.now().microsecondsSinceEpoch}';
    final namespaceB =
        'sqlite-broker-b-${DateTime.now().microsecondsSinceEpoch}';
    final brokerA = await SqliteBroker.open(
      dbFile,
      namespace: namespaceA,
      defaultVisibilityTimeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(milliseconds: 75),
    );
    final brokerB = await SqliteBroker.open(
      dbFile,
      namespace: namespaceB,
      defaultVisibilityTimeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(milliseconds: 75),
    );
    try {
      final queue = 'queue-${DateTime.now().microsecondsSinceEpoch}';
      final envelope = Envelope(
        name: 'sqlite.namespace',
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

  test(
    'queue receipts with broadcast prefix are treated as queue jobs',
    () async {
      final publisher = await SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 25),
        sweeperInterval: const Duration(milliseconds: 75),
      );
      final worker = await SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 25),
        sweeperInterval: const Duration(milliseconds: 75),
      );
      try {
        final queue = 'queue-${DateTime.now().microsecondsSinceEpoch}';
        final deliveries = StreamIterator(
          worker.consume(
            RoutingSubscription.singleQueue(queue),
            consumerName: 'worker-a',
          ),
        );
        Future<Delivery> nextDelivery() async {
          final moved = await deliveries.moveNext().timeout(
            const Duration(seconds: 1),
          );
          expect(moved, isTrue);
          return deliveries.current;
        }

        await publisher.publish(
          Envelope(
            id: 'broadcast:lease',
            name: 'sqlite.prefix.lease',
            args: const {},
            queue: queue,
          ),
        );
        final leaseDelivery = await nextDelivery();
        await worker.extendLease(
          leaseDelivery,
          const Duration(milliseconds: 300),
        );
        expect(await worker.inflightCount(queue), 1);
        await worker.ack(leaseDelivery);
        expect(await worker.pendingCount(queue), 0);

        await publisher.publish(
          Envelope(
            id: 'broadcast:nack',
            name: 'sqlite.prefix.nack',
            args: const {},
            queue: queue,
          ),
        );
        final nackDelivery = await nextDelivery();
        await worker.nack(nackDelivery, requeue: true);
        final redelivered = await nextDelivery();
        expect(redelivered.envelope.id, 'broadcast:nack');
        await worker.ack(redelivered);

        await publisher.publish(
          Envelope(
            id: 'broadcast:deadletter',
            name: 'sqlite.prefix.deadletter',
            args: const {},
            queue: queue,
          ),
        );
        final deadLetterDelivery = await nextDelivery();
        await worker.deadLetter(deadLetterDelivery, reason: 'manual');
        final deadLetters = await worker.listDeadLetters(queue, limit: 20);
        expect(
          deadLetters.entries.map((entry) => entry.envelope.id),
          contains('broadcast:deadletter'),
        );

        await publisher.publish(
          Envelope(
            id: 'broadcast:nack-no-requeue',
            name: 'sqlite.prefix.nack.dead',
            args: const {},
            queue: queue,
          ),
        );
        final nackNoRequeue = await nextDelivery();
        await worker.nack(nackNoRequeue, requeue: false);
        final deadLettersAfterNack = await worker.listDeadLetters(
          queue,
          limit: 20,
        );
        expect(
          deadLettersAfterNack.entries.map((entry) => entry.envelope.id),
          contains('broadcast:nack-no-requeue'),
        );
        await deliveries.cancel();
      } finally {
        await worker.close();
        await publisher.close();
      }
    },
  );
}
