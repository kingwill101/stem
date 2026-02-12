import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryBroker', () {
    test('delivers published messages to consumers', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 50),
        defaultVisibilityTimeout: const Duration(seconds: 1),
      );

      final envelope = Envelope(name: 'task', args: const {});
      await broker.publish(envelope);

      final delivery = await broker
          .consume(RoutingSubscription.singleQueue('default'))
          .first
          .timeout(const Duration(seconds: 1));

      expect(delivery.envelope.id, equals(envelope.id));
      await broker.ack(delivery);
      broker.dispose();
    });

    test('delayed messages become available after ETA', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 50),
      );

      final envelope = Envelope(
        name: 'delayed',
        args: const {},
        notBefore: DateTime.now().add(const Duration(milliseconds: 80)),
      );
      await broker.publish(envelope);

      final stream = broker.consume(RoutingSubscription.singleQueue('default'));
      final delivery = await stream.first.timeout(const Duration(seconds: 1));
      expect(delivery.envelope.name, equals('delayed'));
      await broker.ack(delivery);
      broker.dispose();
    });

    test('expired leases are reclaimed and re-delivered', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
        defaultVisibilityTimeout: const Duration(milliseconds: 30),
      );

      final envelope = Envelope(
        name: 'timeout-task',
        args: const {},
        visibilityTimeout: const Duration(milliseconds: 30),
      );
      await broker.publish(envelope);

      final first = await broker
          .consume(
            RoutingSubscription.singleQueue('default'),
            consumerName: 'c-test',
          )
          .first;
      expect(first.envelope.id, equals(envelope.id));

      // Do not ack; wait for reclaim.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final second = await broker
          .consume(
            RoutingSubscription.singleQueue('default'),
            consumerName: 'c-test',
          )
          .first
          .timeout(const Duration(seconds: 1));
      expect(second.envelope.id, equals(envelope.id));
      await broker.ack(second);
      broker.dispose();
    });

    test('broadcast fan-out delivers to active subscribers', () async {
      final namespace = 'broadcast-${DateTime.now().microsecondsSinceEpoch}';
      final publisher = InMemoryBroker(namespace: namespace);
      final workerOne = InMemoryBroker(namespace: namespace);
      final workerTwo = InMemoryBroker(namespace: namespace);

      try {
        final subscription = RoutingSubscription(
          queues: const ['default'],
          broadcastChannels: const ['ops'],
        );
        final deliveryOne = workerOne.consume(subscription).first;
        final deliveryTwo = workerTwo.consume(subscription).first;

        await publisher.publish(
          Envelope(name: 'broadcast.task', args: const {'value': 'fanout'}),
          routing: RoutingInfo.broadcast(channel: 'ops'),
        );

        final first = await deliveryOne.timeout(const Duration(seconds: 1));
        final second = await deliveryTwo.timeout(const Duration(seconds: 1));

        expect(first.envelope.name, 'broadcast.task');
        expect(first.route.isBroadcast, isTrue);
        expect(first.route.broadcastChannel, 'ops');
        expect(second.envelope.name, 'broadcast.task');
        expect(second.route.isBroadcast, isTrue);
        expect(second.route.broadcastChannel, 'ops');

        await workerOne.ack(first);
        await workerTwo.ack(second);
      } finally {
        publisher.dispose();
        workerOne.dispose();
        workerTwo.dispose();
      }
    });

    test('supports broadcast-only subscriptions', () async {
      final namespace =
          'broadcast-only-${DateTime.now().microsecondsSinceEpoch}';
      final publisher = InMemoryBroker(namespace: namespace);
      final consumer = InMemoryBroker(namespace: namespace);
      try {
        final subscription = RoutingSubscription(
          queues: const [],
          broadcastChannels: const ['ops'],
        );

        final deliveryFuture = consumer.consume(subscription).first;

        await publisher.publish(
          Envelope(name: 'broadcast.only', args: const {'value': 1}),
          routing: RoutingInfo.broadcast(channel: 'ops'),
        );

        final delivery = await deliveryFuture.timeout(
          const Duration(seconds: 1),
        );
        expect(delivery.route.isBroadcast, isTrue);
        expect(delivery.route.broadcastChannel, 'ops');
        expect(delivery.envelope.name, 'broadcast.only');

        await consumer.ack(delivery);
      } finally {
        publisher.dispose();
        consumer.dispose();
      }
    });

    test('broadcast catch-up replays unacked history per consumer', () async {
      final namespace =
          'broadcast-replay-${DateTime.now().microsecondsSinceEpoch}';
      final publisher = InMemoryBroker(namespace: namespace);
      final consumerA = InMemoryBroker(namespace: namespace);
      final consumerB = InMemoryBroker(namespace: namespace);
      try {
        final subscription = RoutingSubscription(
          queues: const [],
          broadcastChannels: const ['ops'],
        );

        await publisher.publish(
          Envelope(name: 'broadcast.replay', args: const {'value': 1}),
          routing: RoutingInfo.broadcast(channel: 'ops'),
        );

        final firstPass = StreamIterator(
          consumerA.consume(subscription, consumerName: 'worker-a'),
        );
        expect(
          await firstPass.moveNext().timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(firstPass.current.envelope.name, 'broadcast.replay');
        await consumerA.ack(firstPass.current);
        await firstPass.cancel();

        final replayCheck = StreamIterator(
          consumerA.consume(subscription, consumerName: 'worker-a'),
        );
        final replayed = await replayCheck.moveNext().timeout(
          const Duration(milliseconds: 200),
          onTimeout: () => false,
        );
        expect(replayed, isFalse);
        await replayCheck.cancel();

        final secondPass = StreamIterator(
          consumerB.consume(subscription, consumerName: 'worker-b'),
        );
        expect(
          await secondPass.moveNext().timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(secondPass.current.envelope.name, 'broadcast.replay');
        await consumerB.ack(secondPass.current);
        await secondPass.cancel();
      } finally {
        publisher.dispose();
        consumerA.dispose();
        consumerB.dispose();
      }
    });

    test('broadcast publishes with reused envelope id are delivered', () async {
      final namespace =
          'broadcast-duplicate-id-${DateTime.now().microsecondsSinceEpoch}';
      final publisher = InMemoryBroker(namespace: namespace);
      final consumer = InMemoryBroker(namespace: namespace);
      final subscription = RoutingSubscription(
        queues: const [],
        broadcastChannels: const ['ops'],
      );
      final iterator = StreamIterator(
        consumer.consume(subscription, consumerName: 'worker-a'),
      );
      try {
        await publisher.publish(
          Envelope(
            id: 'custom-broadcast-id',
            name: 'broadcast.duplicate',
            args: const {'value': 1},
          ),
          routing: RoutingInfo.broadcast(channel: 'ops'),
        );
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(iterator.current.envelope.args['value'], 1);
        await consumer.ack(iterator.current);

        await publisher.publish(
          Envelope(
            id: 'custom-broadcast-id',
            name: 'broadcast.duplicate',
            args: const {'value': 2},
          ),
          routing: RoutingInfo.broadcast(channel: 'ops'),
        );
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(iterator.current.envelope.args['value'], 2);
        await consumer.ack(iterator.current);
      } finally {
        await iterator.cancel();
        publisher.dispose();
        consumer.dispose();
      }
    });
  });

  group('InMemoryResultBackend', () {
    test('stores and expires task statuses', () async {
      final backend = InMemoryResultBackend(
        defaultTtl: const Duration(milliseconds: 50),
      );

      await backend.set(
        'task-1',
        TaskState.succeeded,
        payload: {'value': 1},
        meta: const {'queue': 'default'},
      );

      final status = await backend.get('task-1');
      expect(status, isNotNull);
      expect(status!.payload, equals({'value': 1}));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final expired = await backend.get('task-1');
      expect(expired, isNull);
    });

    test('preserves signature metadata', () async {
      final backend = InMemoryResultBackend();

      const signatureMeta = {
        'stem-signature': 'sig-value',
        'stem-signature-key': 'key-1',
      };

      await backend.set(
        'signed-task',
        TaskState.succeeded,
        meta: signatureMeta,
      );

      final status = await backend.get('signed-task');
      expect(status, isNotNull);
      expect(status!.meta['stem-signature'], equals('sig-value'));
      expect(status.meta['stem-signature-key'], equals('key-1'));
    });

    test('aggregates group results', () async {
      final backend = InMemoryResultBackend();

      await backend.initGroup(GroupDescriptor(id: 'g1', expected: 2));

      await backend.addGroupResult(
        'g1',
        TaskStatus(id: 't1', state: TaskState.succeeded, attempt: 0),
      );

      final status = await backend.addGroupResult(
        'g1',
        TaskStatus(id: 't2', state: TaskState.succeeded, attempt: 0),
      );

      expect(status, isNotNull);
      expect(status!.isComplete, isTrue);
      expect(status.results.length, equals(2));
    });
  });

  group('Integration', () {
    test('publish -> consume -> ack success', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 30),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue('noop');
      final delivery = await broker
          .consume(RoutingSubscription.singleQueue('default'))
          .first;

      await backend.set(taskId, TaskState.succeeded);
      await broker.ack(delivery);

      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.succeeded));

      broker.dispose();
    });

    test('failed task moves to dead letter', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 30),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue('noop');
      final delivery = await broker
          .consume(RoutingSubscription.singleQueue('default'))
          .first;

      await backend.set(
        taskId,
        TaskState.failed,
        error: const TaskError(
          type: 'Failure',
          message: 'boom',
        ),
        attempt: 1,
      );
      await broker.deadLetter(delivery, reason: 'test');

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, hasLength(1));
      expect(deadPage.entries.single.reason, equals('test'));

      broker.dispose();
    });
  });
}

class _NoopTask implements TaskHandler<void> {
  @override
  String get name => 'noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
