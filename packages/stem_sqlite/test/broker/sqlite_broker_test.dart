import 'dart:async';
import 'dart:io';

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

  group('consumer drain', () {
    for (final operation in ['cancel', 'close', 'cancel then close']) {
      test(
        '$operation joins a blocked claim and '
        'releases only un-emitted work',
        () async {
          final broker = await SqliteBroker.open(
            dbFile,
            pollInterval: const Duration(hours: 1),
            sweeperInterval: Duration.zero,
          );
          final blocker = await SqliteConnections.open(dbFile);
          addTearDown(broker.close);
          addTearDown(blocker.close);
          await broker.publish(
            Envelope(name: 'drain', args: const {}, queue: 'drain'),
          );
          final entered = Completer<void>();
          final release = Completer<void>();
          final transaction = blocker.runInTransaction((_) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          final deliveries = <Delivery>[];
          final subscription = broker
              .consume(RoutingSubscription.singleQueue('drain'), prefetch: 3)
              .listen(deliveries.add);
          final cancellation = operation == 'close'
              ? Future<void>.value()
              : subscription.cancel();
          final drain = operation == 'cancel' ? cancellation : broker.close();
          var drained = false;
          unawaited(drain.then((_) => drained = true));
          try {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            expect(drained, isFalse);
            if (operation != 'cancel') {
              expect(identical(broker.close(), drain), isTrue);
            }
          } finally {
            release.complete();
            await transaction;
          }
          await drain.timeout(const Duration(seconds: 3));
          await cancellation;
          expect(deliveries, isEmpty);
          final observer = await SqliteBroker.open(dbFile);
          addTearDown(observer.close);
          expect(await observer.inflightCount('drain'), 0);
          expect(await observer.pendingCount('drain'), 1);
        },
      );
    }

    test('close interrupts polling and joins repeated close calls', () async {
      final broker = await SqliteBroker.open(
        dbFile,
        pollInterval: const Duration(hours: 1),
        sweeperInterval: Duration.zero,
      );
      addTearDown(broker.close);
      final done = Completer<void>();
      broker
          .consume(RoutingSubscription.singleQueue('empty'))
          .listen((_) => fail('Unexpected delivery'), onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final closing = broker.close();
      expect(identical(broker.close(), closing), isTrue);
      await closing.timeout(const Duration(seconds: 3));
      await done.future.timeout(const Duration(seconds: 3));
      expect(
        () => broker.consume(RoutingSubscription.singleQueue('empty')),
        throwsStateError,
      );
    });

    test('one listener cancelling does not stop other listeners', () async {
      final broker = await SqliteBroker.open(
        dbFile,
        pollInterval: const Duration(milliseconds: 5),
        sweeperInterval: Duration.zero,
      );
      addTearDown(broker.close);
      final stream = broker.consume(RoutingSubscription.singleQueue('shared'));
      expect(stream.isBroadcast, isTrue);
      final first = stream.listen((_) {});
      final received = Completer<Delivery>();
      final second = stream.listen(received.complete);
      addTearDown(second.cancel);
      await first.cancel();
      await broker.publish(
        Envelope(name: 'shared', args: const {}, queue: 'shared'),
      );
      final delivery = await received.future.timeout(
        const Duration(seconds: 3),
      );
      await second.cancel();
      expect(await broker.inflightCount('shared'), 1);
      await broker.ack(delivery);
      expect(await broker.inflightCount('shared'), 0);
    });
  });

  group('queue prefetch', () {
    late SqliteBroker broker;
    late SqliteBroker other;
    final deliveries = <Delivery>[];

    setUp(() async {
      deliveries.clear();
      broker = await SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 10),
        sweeperInterval: Duration.zero,
      );
      other = await SqliteBroker.open(dbFile);
      for (var i = 0; i < 4; i++) {
        await broker.publish(
          Envelope(name: 'prefetch', args: const {}, queue: 'prefetch'),
        );
      }
    });

    tearDown(() async {
      await other.close();
      await broker.close();
    });

    Future<void> waitForCount(int count) async {
      await (() async {
        while (deliveries.length < count) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      })().timeout(const Duration(seconds: 3));
    }

    Future<void> expectCount(int count) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(deliveries, hasLength(count));
    }

    for (final settlement in ['ack', 'requeue', 'deadLetter', 'nack']) {
      test(
        '$settlement frees exactly one slot across broker handles',
        () async {
          final subscription = broker
              .consume(
                RoutingSubscription.singleQueue('prefetch'),
                prefetch: 2,
              )
              .listen(deliveries.add);
          addTearDown(subscription.cancel);
          await waitForCount(2);
          await expectCount(2);
          expect(await broker.inflightCount('prefetch'), 2);
          final first = deliveries.first;
          switch (settlement) {
            case 'ack':
              await other.ack(first);
            case 'requeue':
              await other.nack(first);
            case 'deadLetter':
              await other.deadLetter(first);
            case 'nack':
              await other.nack(first, requeue: false);
          }
          await waitForCount(3);
          await expectCount(3);
          expect(await broker.inflightCount('prefetch'), 2);
        },
      );
    }

    test('lease extension retains a slot and expiry releases it', () async {
      final subscription = broker
          .consume(RoutingSubscription.singleQueue('prefetch'))
          .listen(deliveries.add);
      addTearDown(subscription.cancel);
      await waitForCount(1);
      await other.extendLease(
        deliveries.first,
        const Duration(milliseconds: 400),
      );
      await other.extendLease(
        deliveries.first,
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await expectCount(1);
      await waitForCount(2);
      await expectCount(2);
    });

    test('consumer names do not share prefetch capacity', () async {
      final streams = [
        for (var i = 0; i < 2; i++)
          broker
              .consume(
                RoutingSubscription.singleQueue('prefetch'),
                consumerName: 'same-name',
              )
              .listen(deliveries.add),
      ];
      addTearDown(() async {
        for (final stream in streams) {
          await stream.cancel();
        }
      });
      await waitForCount(2);
      await expectCount(2);
      expect(
        deliveries.map((delivery) => delivery.envelope.id).toSet(),
        hasLength(2),
      );
    });

    test('cancellation leaves unclaimed work available', () async {
      final subscription = broker
          .consume(RoutingSubscription.singleQueue('prefetch'))
          .listen(deliveries.add);
      await waitForCount(1);
      await subscription.cancel();
      await expectCount(1);
      expect(await broker.inflightCount('prefetch'), 1);
      expect(await broker.pendingCount('prefetch'), 3);
    });
  });

  test(
    'repeated nack without requeue updates one dead-letter record',
    () async {
      final broker = await SqliteBroker.open(
        dbFile,
        pollInterval: const Duration(milliseconds: 10),
        sweeperInterval: Duration.zero,
      );
      addTearDown(broker.close);
      const queue = 'repeated-nack-dead-letter';
      final deliveries = StreamIterator(
        broker.consume(RoutingSubscription.singleQueue(queue)),
      );
      try {
        for (var attempt = 0; attempt < 2; attempt++) {
          await broker.publish(
            Envelope(
              id: 'repeated-nack-task',
              name: 'sqlite.repeated.nack',
              args: const {},
              queue: queue,
              attempt: attempt,
              maxRetries: 5,
            ),
          );
          expect(
            await deliveries.moveNext().timeout(const Duration(seconds: 5)),
            isTrue,
          );
          await broker.nack(deliveries.current, requeue: false);
        }
      } finally {
        await deliveries.cancel();
      }

      final deadLetters = await broker.listDeadLetters(queue, limit: 10);
      expect(deadLetters.entries, hasLength(1));
      expect(deadLetters.entries.single.envelope.id, 'repeated-nack-task');
      expect(deadLetters.entries.single.envelope.attempt, 1);
      expect(await broker.pendingCount(queue), 0);
      expect(await broker.inflightCount(queue), 0);
    },
  );

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

  runQueueEventsContractTests(
    adapterName: 'SQLite',
    factory: QueueEventsContractFactory(
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
      additionalDispose: (broker) => (broker as SqliteBroker).close(),
    ),
  );

  test('fromDataSource runs migrations', () async {
    final dataSource = buildOrmRegistry().sqliteFileDataSource(
      path: dbFile.path,
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
        await worker.nack(nackDelivery);
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
