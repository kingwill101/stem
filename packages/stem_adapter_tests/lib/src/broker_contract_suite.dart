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
    this.requeueTimeout = const Duration(seconds: 5),
    this.concurrentPublishTimeout = const Duration(seconds: 1),
    this.concurrentDeliveryTimeout = const Duration(seconds: 5),
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

  /// Maximum time to wait for a requeued delivery to appear.
  final Duration requeueTimeout;

  /// Maximum time allowed for publish to complete while other consumers are active.
  final Duration concurrentPublishTimeout;

  /// Maximum time to wait for a delivery in concurrent consumer scenarios.
  final Duration concurrentDeliveryTimeout;
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

      final firstDelivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(firstDelivery, isNotNull);
      expect(firstDelivery!.envelope.id, envelope.id);
      await currentBroker.ack(firstDelivery);

      final confirmation = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: settings.queueSettleDelay * 5,
      );
      expect(
        confirmation,
        isNull,
        reason: 'Queue $queue should be empty after ack',
      );

      await _purgeAll(currentBroker, queue);
    });

    test('publish respects routing queue overrides', () async {
      final currentBroker = broker!;
      final queueA = _queueName('routing-a');
      final queueB = _queueName('routing-b');
      final envelope = Envelope(
        name: 'contract.route.override',
        args: const {},
        queue: queueA,
      );

      await currentBroker.publish(
        envelope,
        routing: RoutingInfo.queue(queue: queueB),
      );

      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queueB,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(delivery, isNotNull);
      if (delivery != null) {
        await currentBroker.ack(delivery);
      }

      final wrongQueue = await _expectDelivery(
        broker: currentBroker,
        queue: queueA,
        pollTimeout: settings.queueSettleDelay * 3,
      );
      expect(
        wrongQueue,
        isNull,
        reason: 'Routing overrides should not enqueue to $queueA',
      );

      await _purgeAll(currentBroker, queueA);
      await _purgeAll(currentBroker, queueB);
    });

    test('pending/inflight counts track delivery lifecycle', () async {
      final currentBroker = broker!;
      final queue = _queueName('counts');
      final pendingBefore = await currentBroker.pendingCount(queue);
      final inflightBefore = await currentBroker.inflightCount(queue);
      if (pendingBefore == null && inflightBefore == null) {
        return;
      }

      final envelope = Envelope(
        name: 'contract.counts',
        args: const {},
        queue: queue,
      );
      await currentBroker.publish(envelope);

      if (pendingBefore != null) {
        await _waitFor<int?>(
          evaluate: () => currentBroker.pendingCount(queue),
          predicate: (value) => (value ?? 0) >= 1,
          timeout: settings.queueSettleDelay * 5,
          pollInterval: settings.queueSettleDelay,
        );
      }

      final iterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      Delivery? delivery;
      try {
        delivery = await _nextIteratorDelivery(
          iterator: iterator,
          timeout: const Duration(seconds: 5),
        );
        expect(delivery, isNotNull);

        if (inflightBefore != null) {
          await _waitFor<int?>(
            evaluate: () => currentBroker.inflightCount(queue),
            predicate: (value) => (value ?? 0) >= 1,
            timeout: settings.queueSettleDelay * 5,
            pollInterval: settings.queueSettleDelay,
          );
        }

        if (pendingBefore != null) {
          await _waitFor<int?>(
            evaluate: () => currentBroker.pendingCount(queue),
            predicate: (value) => (value ?? 0) == 0,
            timeout: settings.queueSettleDelay * 5,
            pollInterval: settings.queueSettleDelay,
          );
        }
      } finally {
        if (delivery != null) {
          await currentBroker.ack(delivery);
        }
        await iterator.cancel();
      }

      if (inflightBefore != null) {
        await _waitFor<int?>(
          evaluate: () => currentBroker.inflightCount(queue),
          predicate: (value) => (value ?? 0) == 0,
          timeout: settings.queueSettleDelay * 5,
          pollInterval: settings.queueSettleDelay,
        );
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

        final iterator = StreamIterator(
          currentBroker.consume(RoutingSubscription.singleQueue(queue)),
        );
        try {
          final delivery = await _nextIteratorDelivery(
            iterator: iterator,
            timeout: const Duration(seconds: 5),
          );
          expect(delivery, isNotNull);
          await currentBroker.nack(delivery!, requeue: true);

          final redelivery = await _nextIteratorDelivery(
            iterator: iterator,
            timeout: settings.requeueTimeout,
          );
          expect(redelivery, isNotNull);
          await currentBroker.ack(redelivery!);
        } finally {
          await iterator.cancel();
        }

        await _purgeAll(currentBroker, queue);
      },
    );

    test('nack with requeue=false does not re-deliver the job', () async {
      final currentBroker = broker!;
      final queue = _queueName('nack-drop');
      final envelope = Envelope(
        name: 'contract.nack.drop',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);

      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(delivery, isNotNull);
      await currentBroker.nack(delivery!, requeue: false);

      final redelivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: settings.queueSettleDelay * 4,
      );
      expect(
        redelivery,
        isNull,
        reason: 'nack without requeue should not re-deliver the job',
      );

      await _purgeAll(currentBroker, queue);
    });

    test('deadLetter moves the job to the dead letter queue', () async {
      final currentBroker = broker!;
      final queue = _queueName('dead-letter');
      final envelope = Envelope(
        name: 'contract.dlq',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);

      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(delivery, isNotNull);
      await currentBroker.deadLetter(delivery!, reason: 'contract-test');

      final page = await _waitFor<DeadLetterPage>(
        evaluate: () => currentBroker.listDeadLetters(queue, limit: 10),
        predicate: (page) => page.entries
            .map((entry) => entry.envelope.id)
            .contains(envelope.id),
        timeout: settings.queueSettleDelay * 5,
        pollInterval: settings.queueSettleDelay,
      );
      expect(
        page.entries.map((entry) => entry.envelope.id),
        contains(envelope.id),
      );

      await _purgeAll(currentBroker, queue);
    });

    test('dead letter entries are retrievable and purgeable', () async {
      final currentBroker = broker!;
      final queue = _queueName('dead-letter-get');
      final envelope = Envelope(
        name: 'contract.dead.get',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);

      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(delivery, isNotNull);
      await currentBroker.deadLetter(
        delivery!,
        reason: 'contract-get',
        meta: const {'source': 'contract', 'severity': 'low'},
      );

      final entry = await currentBroker.getDeadLetter(queue, envelope.id);
      expect(entry, isNotNull);
      expect(entry!.envelope.id, envelope.id);
      expect(entry.reason, 'contract-get');
      expect(entry.meta['source'], 'contract');
      expect(entry.meta['severity'], 'low');

      final purged = await currentBroker.purgeDeadLetters(queue);
      expect(purged, greaterThanOrEqualTo(1));

      final afterPurge = await currentBroker.listDeadLetters(queue, limit: 1);
      expect(afterPurge.entries, isEmpty);
    });

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
      final afterDryRun = await currentBroker.getDeadLetter(queue, envelope.id);
      expect(afterDryRun, isNotNull);

      final replay = await currentBroker.replayDeadLetters(queue, limit: 10);
      expect(replay.dryRun, isFalse);
      final replayedIds = await _waitFor<Iterable<String>>(
        evaluate: () async => replay.entries.map((entry) => entry.envelope.id),
        predicate: (ids) => ids.contains(envelope.id),
        timeout: settings.queueSettleDelay * 5,
        pollInterval: settings.queueSettleDelay,
      );
      expect(replayedIds, contains(envelope.id));

      await Future<void>.delayed(settings.replayDelay);

      final retryIterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      final retryTimeout = Duration(
        milliseconds: settings.requeueTimeout.inMilliseconds * 2,
      );
      final retry = await _nextIteratorDelivery(
        iterator: retryIterator,
        timeout: retryTimeout,
      );
      expect(retry, isNotNull);
      if (retry != null) {
        expect(retry.envelope.id, envelope.id);
        await currentBroker.ack(retry);
      }
      await retryIterator.cancel();

      await _purgeAll(currentBroker, queue);
    });

    test('replayDeadLetters respects delay scheduling', () async {
      final currentBroker = broker!;
      final queue = _queueName('replay-delay');
      final envelope = Envelope(
        name: 'contract.replay.delay',
        args: const {},
        queue: queue,
      );

      await currentBroker.publish(envelope);
      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(delivery, isNotNull);
      await currentBroker.deadLetter(delivery!, reason: 'contract-delay');

      final delay = _scaledDelay(settings.queueSettleDelay);
      final replay = await currentBroker.replayDeadLetters(
        queue,
        limit: 10,
        delay: delay,
      );
      expect(replay.dryRun, isFalse);

      final early = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: delay ~/ 2,
      );
      expect(
        early,
        isNull,
        reason: 'Replay delay should keep job hidden until due',
      );

      await Future<void>.delayed(delay + settings.queueSettleDelay);
      final later = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: settings.requeueTimeout,
      );
      expect(later, isNotNull);
      if (later != null) {
        await currentBroker.ack(later);
      }

      await _purgeAll(currentBroker, queue);
    });

    test('concurrent subscriptions do not block publish', () async {
      final currentBroker = broker!;
      final queueA = _queueName('concurrent-a');
      final queueB = _queueName('concurrent-b');
      final iteratorA = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queueA)),
      );
      final iteratorB = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queueB)),
      );
      try {
        await Future<void>.delayed(settings.queueSettleDelay);

        final envelope = Envelope(
          name: 'contract.concurrent.publish',
          args: const {},
          queue: queueB,
        );

        final publishWatch = Stopwatch()..start();
        await currentBroker.publish(envelope);
        publishWatch.stop();

        expect(
          publishWatch.elapsed,
          lessThan(settings.concurrentPublishTimeout),
          reason: 'publish should not be delayed by another consumer',
        );

        final delivery = await _nextIteratorDelivery(
          iterator: iteratorB,
          timeout: settings.concurrentDeliveryTimeout,
        );
        expect(delivery, isNotNull);
        await currentBroker.ack(delivery!);
      } finally {
        await iteratorA.cancel();
        await iteratorB.cancel();
      }

      await _purgeAll(currentBroker, queueA);
      await _purgeAll(currentBroker, queueB);
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

      final pending = await _waitFor<int?>(
        evaluate: () => currentBroker.pendingCount(queue),
        predicate: (value) => value == null || value == 0,
        timeout: settings.queueSettleDelay * 5,
        pollInterval: settings.queueSettleDelay,
      );
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
      final maxWait = settings.requeueTimeout > totalDelay
          ? settings.requeueTimeout
          : totalDelay;

      final laterIterator = StreamIterator(
        currentBroker.consume(RoutingSubscription.singleQueue(queue)),
      );
      final redelivery = await _nextIteratorDelivery(
        iterator: laterIterator,
        timeout: maxWait,
      );
      expect(redelivery, isNotNull);
      expect(redelivery!.envelope.id, delivery.envelope.id);
      await currentBroker.ack(redelivery);
      await laterIterator.cancel();

      await _purgeAll(currentBroker, queue);
    });

    test('unacked jobs become visible again after the lease expires', () async {
      final currentBroker = broker!;
      final queue = _queueName('lease-expiry');
      final envelope = Envelope(
        name: 'contract.lease.expiry',
        args: const {},
        queue: queue,
        visibilityTimeout: settings.visibilityTimeout,
      );

      await currentBroker.publish(envelope);

      final firstDelivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: const Duration(seconds: 5),
      );
      expect(firstDelivery, isNotNull);

      await Future<void>.delayed(
        settings.visibilityTimeout + settings.queueSettleDelay,
      );

      final redelivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: settings.requeueTimeout,
      );
      expect(
        redelivery,
        isNotNull,
        reason: 'Expected unacked delivery to become visible again',
      );
      if (redelivery != null) {
        await currentBroker.ack(redelivery);
      }

      await _purgeAll(currentBroker, queue);
    });

    test('delayed jobs are not visible until their scheduled time', () async {
      final currentBroker = broker!;
      if (!currentBroker.supportsDelayed) {
        return;
      }
      final queue = _queueName('delayed');
      final delay = _scaledDelay(settings.queueSettleDelay);
      final envelope = Envelope(
        name: 'contract.delayed',
        args: const {},
        queue: queue,
        notBefore: DateTime.now().add(delay),
      );

      await currentBroker.publish(envelope);

      final pendingBefore = await currentBroker.pendingCount(queue);
      if (pendingBefore != null) {
        expect(
          pendingBefore,
          equals(0),
          reason: 'Delayed jobs should not count as pending yet',
        );
      }

      await Future<void>.delayed(delay + settings.queueSettleDelay);

      final delivery = await _expectDelivery(
        broker: currentBroker,
        queue: queue,
        pollTimeout: settings.requeueTimeout,
      );
      expect(delivery, isNotNull);
      if (delivery != null) {
        await currentBroker.ack(delivery);
      }

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
  try {
    await broker.purgeDeadLetters(queue);
  } catch (_) {
    // Some adapters may not support dead letter purging or may throw due to
    // driver return types. Ignore cleanup failures in contract tests.
  }
}

int _queueCounter = 0;
String _queueName(String prefix) {
  final id = ++_queueCounter;
  return 'stem-contract-$prefix-$id';
}

Future<T> _waitFor<T>({
  required Future<T> Function() evaluate,
  required bool Function(T value) predicate,
  required Duration timeout,
  required Duration pollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  late T result;
  while (true) {
    result = await evaluate();
    if (predicate(result)) {
      return result;
    }
    if (DateTime.now().isAfter(deadline)) {
      return result;
    }
    await Future<void>.delayed(pollInterval);
  }
}

Future<Delivery?> _nextIteratorDelivery({
  required StreamIterator<Delivery> iterator,
  required Duration timeout,
}) async {
  final hasNext = await iterator.moveNext().timeout(
    timeout,
    onTimeout: () => false,
  );
  if (!hasNext) {
    return null;
  }
  return iterator.current;
}

Future<Delivery?> _expectDelivery({
  required Broker broker,
  required String queue,
  int prefetch = 1,
  Duration pollTimeout = const Duration(seconds: 5),
  String? consumerGroup,
  String? consumerName,
}) async {
  final iterator = StreamIterator(
    broker.consume(
      RoutingSubscription.singleQueue(queue),
      prefetch: prefetch,
      consumerGroup: consumerGroup,
      consumerName: consumerName,
    ),
  );
  try {
    final hasNext = await iterator.moveNext().timeout(
      pollTimeout,
      onTimeout: () => false,
    );
    if (!hasNext) {
      return null;
    }
    return iterator.current;
  } finally {
    await iterator.cancel();
  }
}

Duration _scaledDelay(Duration base) {
  final ms = base.inMilliseconds * 4;
  return Duration(milliseconds: ms <= 0 ? 200 : ms);
}
