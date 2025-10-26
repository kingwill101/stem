import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class BrokerContractSettings {
  const BrokerContractSettings({
    this.visibilityTimeout = const Duration(seconds: 1),
    this.leaseExtension = const Duration(milliseconds: 750),
    this.queueSettleDelay = const Duration(milliseconds: 150),
    this.replayDelay = const Duration(milliseconds: 200),
    this.verifyPriorityOrdering = true,
    this.verifyBroadcastFanout = false,
  });

  /// Expected default visibility timeout used by the adapter under test.
  final Duration visibilityTimeout;

  /// Duration that should meaningfully extend the lease for a delivery.
  final Duration leaseExtension;

  /// Additional wait time after queue mutations to allow eventual consistency.
  final Duration queueSettleDelay;

  /// Wait time after dead-letter replay to allow the job to become visible again.
  final Duration replayDelay;

  /// Whether to verify priority ordering when the adapter reports support.
  final bool verifyPriorityOrdering;

  /// Whether to run the broadcast fan-out scenario (requires additional
  /// broker instances supplied through the factory).
  final bool verifyBroadcastFanout;
}

class BrokerContractFactory {
  const BrokerContractFactory({
    required this.create,
    this.dispose,
    this.additionalBrokerFactory,
  });

  /// Returns a fresh broker instance for each test case.
  final Future<Broker> Function() create;

  /// Optional disposer invoked after each test. When omitted the broker is
  /// closed via [Broker.close].
  final FutureOr<void> Function(Broker broker)? dispose;

  /// Optional factory for creating additional broker instances used by
  /// scenarios requiring multiple connections (for example broadcast fan-out).
  final Future<Broker> Function()? additionalBrokerFactory;
}

/// Runs the canonical broker contract test suite for an adapter.
void runBrokerContractTests({
  required String adapterName,
  required BrokerContractFactory factory,
  BrokerContractSettings settings = const BrokerContractSettings(),
}) {
  group('$adapterName broker contract', () {
    Broker? broker;

    setUp(() async {
      broker = await factory.create();
    });

    tearDown(() async {
      final instance = broker;
      if (instance == null) {
        return;
      }
      if (factory.dispose != null) {
        await factory.dispose!(instance);
      }
      broker = null;
    });

    test('publish → consume → ack removes the job', () async {
      final currentBroker = broker!;
      final queue = _queueName('basic');
      final envelope = Envelope(
        name: 'contract.basic',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);

      final iterator = StreamIterator(
        currentBroker.consume(
          RoutingSubscription.singleQueue(queue),
          prefetch: 1,
        ),
      );

      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final delivery = iterator.current;
      expect(delivery.envelope.id, envelope.id);
      await currentBroker.ack(delivery);
      await iterator.cancel();

      final pending = await currentBroker.pendingCount(queue);
      if (pending != null) {
        expect(pending, equals(0));
      }

      await _purgeAll(currentBroker, queue);
    });

    test(
      'nack with requeue=true schedules the job for another attempt',
      () async {
        final currentBroker = broker!;
        final queue = _queueName('nack-requeue');
        final envelope = Envelope(
          name: 'contract.nack.requeue',
          args: const {},
          queue: queue,
        );

        await currentBroker.publish(envelope);

        final firstIterator = StreamIterator(
          currentBroker.consume(RoutingSubscription.singleQueue(queue)),
        );

        expect(
          await firstIterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        final delivery = firstIterator.current;
        await currentBroker.nack(delivery, requeue: true);
        await firstIterator.cancel();

        await Future<void>.delayed(settings.queueSettleDelay);

        final secondIterator = StreamIterator(
          currentBroker.consume(RoutingSubscription.singleQueue(queue)),
        );

        expect(
          await secondIterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        final redelivery = secondIterator.current;
        expect(redelivery.envelope.id, delivery.envelope.id);
        await currentBroker.ack(redelivery);
        await secondIterator.cancel();

        await _purgeAll(currentBroker, queue);
      },
    );

    test(
      'nack with requeue=false moves the job to the dead letter queue',
      () async {
        final currentBroker = broker!;
        final queue = _queueName('dead-letter');
        final envelope = Envelope(
          name: 'contract.dlq',
          args: const {},
          queue: queue,
        );

        await currentBroker.publish(envelope);

        final iterator = StreamIterator(
          currentBroker.consume(RoutingSubscription.singleQueue(queue)),
        );
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        final delivery = iterator.current;
        await currentBroker.nack(delivery, requeue: false);
        await iterator.cancel();

        await Future<void>.delayed(settings.queueSettleDelay);

        final page = await currentBroker.listDeadLetters(queue, limit: 10);
        expect(
          page.entries.map((entry) => entry.envelope.id),
          contains(envelope.id),
        );

        await _purgeAll(currentBroker, queue);
      },
    );

    test('deadLetter + replay requeues failed jobs', () async {
      final currentBroker = broker!;
      final queue = _queueName('replay');
      final envelope = Envelope(
        name: 'contract.replay',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);
      final iterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final delivery = iterator.current;
      await currentBroker.deadLetter(delivery, reason: 'contract-test');
      await iterator.cancel();

      final dryRun = await currentBroker.replayDeadLetters(
        queue,
        limit: 10,
        dryRun: true,
      );
      expect(dryRun.dryRun, isTrue);

      final replay = await currentBroker.replayDeadLetters(queue, limit: 10);
      expect(replay.dryRun, isFalse);
      expect(
        replay.entries.map((entry) => entry.envelope.id),
        contains(envelope.id),
      );

      await Future<void>.delayed(settings.replayDelay);

      final retryIterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      expect(
        await retryIterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final retry = retryIterator.current;
      expect(retry.envelope.id, envelope.id);
      await currentBroker.ack(retry);
      await retryIterator.cancel();

      await _purgeAll(currentBroker, queue);
    });

    test('purge removes pending jobs and clears dead letters', () async {
      final currentBroker = broker!;
      final queue = _queueName('purge');
      final envelope = Envelope(
        name: 'contract.purge',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);
      await currentBroker.purge(queue);

      final pending = await currentBroker.pendingCount(queue);
      if (pending != null) {
        expect(pending, equals(0));
      }

      final deadLetters = await currentBroker.purgeDeadLetters(queue);
      expect(deadLetters, equals(0));
    });

    test('extendLease delays redelivery until the extended deadline', () async {
      final currentBroker = broker!;
      final queue = _queueName('extend-lease');
      final envelope = Envelope(
        name: 'contract.extend',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);

      final iterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final delivery = iterator.current;

      await currentBroker.extendLease(delivery, settings.leaseExtension);
      await iterator.cancel();

      final earlyIterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );

      final earlyResult = await earlyIterator.moveNext().timeout(
        settings.visibilityTimeout ~/ 2,
        onTimeout: () => false,
      );
      expect(
        earlyResult,
        isFalse,
        reason: 'Job should remain invisible during lease',
      );
      await earlyIterator.cancel();

      final totalDelay =
          settings.visibilityTimeout +
          settings.leaseExtension +
          settings.queueSettleDelay;
      await Future<void>.delayed(totalDelay);

      final laterIterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      expect(
        await laterIterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final redelivery = laterIterator.current;
      expect(redelivery.envelope.id, delivery.envelope.id);
      await currentBroker.ack(redelivery);
      await laterIterator.cancel();

      await _purgeAll(currentBroker, queue);
    });
    if (settings.verifyPriorityOrdering) {
      test('priority ordering surfaces higher priority jobs first', () async {
        final currentBroker = broker!;
        if (!currentBroker.supportsPriority) {
          return;
        }

        final queue = _queueName('priority');
        final lowPriority = Envelope(
          name: 'contract.priority.low',
          args: const {'value': 'low'},
          queue: queue,
          priority: 1,
        );
        final highPriority = Envelope(
          name: 'contract.priority.high',
          args: const {'value': 'high'},
          queue: queue,
          priority: 9,
        );

        await currentBroker.publish(
          lowPriority,
          routing: RoutingInfo.queue(
            queue: queue,
            priority: lowPriority.priority,
          ),
        );
        await currentBroker.publish(
          highPriority,
          routing: RoutingInfo.queue(
            queue: queue,
            priority: highPriority.priority,
          ),
        );

        final iterator = StreamIterator(
          currentBroker.consume(
            RoutingSubscription.singleQueue(queue),
            prefetch: 2,
          ),
        );

        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current.envelope.id, highPriority.id);
        await currentBroker.ack(iterator.current);

        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current.envelope.id, lowPriority.id);
        await currentBroker.ack(iterator.current);
        await iterator.cancel();

        await _purgeAll(currentBroker, queue);
      });
    }

    if (settings.verifyBroadcastFanout &&
        factory.additionalBrokerFactory != null) {
      test('broadcast fan-out delivers to all subscribers', () async {
        final publisher = broker!;
        final workerOne = await factory.additionalBrokerFactory!();
        final workerTwo = await factory.additionalBrokerFactory!();

        try {
          final queue = _queueName('broadcast');
          final channel = '${queue}_broadcast';
          final subscription = RoutingSubscription(
            queues: [queue],
            broadcastChannels: [channel],
          );

          final futureOne = workerOne.consume(subscription).first;
          final futureTwo = workerTwo.consume(subscription).first;

          await publisher.publish(
            Envelope(
              name: 'contract.broadcast',
              args: const {'value': 'fanout'},
              queue: queue,
            ),
            routing: RoutingInfo.broadcast(channel: channel),
          );

          final deliveryOne = await futureOne.timeout(
            const Duration(seconds: 5),
          );
          final deliveryTwo = await futureTwo.timeout(
            const Duration(seconds: 5),
          );

          expect(deliveryOne.envelope.name, 'contract.broadcast');
          expect(deliveryTwo.envelope.name, 'contract.broadcast');

          await workerOne.ack(deliveryOne);
          await workerTwo.ack(deliveryTwo);
        } finally {
          if (factory.dispose != null) {
            await factory.dispose!(workerOne);
            await factory.dispose!(workerTwo);
          }
        }
      });
    }
  });
}

Future<void> _purgeAll(Broker broker, String queue) async {
  await broker.purge(queue);
  await broker.purgeDeadLetters(queue);
}

int _queueCounter = 0;
String _queueName(String prefix) {
  final id = ++_queueCounter;
  return 'stem-contract-$prefix-$id';
}
