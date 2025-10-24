import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:stem/src/brokers/redis_broker.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:test/test.dart';

void main() {
  final redisUrl = Platform.environment['STEM_TEST_REDIS_URL'];
  if (redisUrl == null || redisUrl.isEmpty) {
    test(
      'Redis broker integration requires STEM_TEST_REDIS_URL',
      () {},
      skip: 'Set STEM_TEST_REDIS_URL to run Redis broker integration tests.',
    );
    return;
  }

  test('Redis broker end-to-end', () async {
    final namespace = _uniqueNamespace();
    final broker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    try {
      final queue = _uniqueQueue();
      final first = Envelope(
        name: 'integration.redis.echo',
        args: const {'value': 'hi'},
        queue: queue,
      );
      final second = Envelope(
        name: 'integration.redis.echo',
        args: const {'value': 'second'},
        queue: queue,
      );

      await broker.publish(first);
      await broker.publish(second);

      final iterator = StreamIterator(
        broker.consume(RoutingSubscription.singleQueue(queue), prefetch: 1),
      );
      expect(await iterator.moveNext(), isTrue);
      final delivery = iterator.current;
      expect(delivery.envelope.id, first.id);

      await broker.nack(delivery, requeue: true);

      expect(await iterator.moveNext(), isTrue);
      final secondDelivery = iterator.current;
      expect(secondDelivery.envelope.name, second.name);
      expect(secondDelivery.envelope.args, second.args);
      await broker.ack(secondDelivery);

      expect(await iterator.moveNext(), isTrue);
      final redelivered = iterator.current;
      expect(redelivered.envelope.id, first.id);
      expect(redelivered.envelope.attempt, delivery.envelope.attempt + 1);
      await broker.ack(redelivered);
      await iterator.cancel();

      expect(await broker.inflightCount(queue), 0);
      await broker.purge(queue);
    } finally {
      await _safeCloseRedisBroker(broker);
    }
  });

  test('Redis broker honours priority ordering', () async {
    final namespace = _uniqueNamespace();
    final broker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    try {
      final queue = _uniqueQueue();
      final lowPriority = Envelope(
        name: 'integration.redis.low',
        args: const {'value': 'low'},
        queue: queue,
        priority: 1,
      );
      final highPriority = Envelope(
        name: 'integration.redis.high',
        args: const {'value': 'high'},
        queue: queue,
        priority: 9,
      );

      await broker.publish(
        lowPriority,
        routing: RoutingInfo.queue(
          queue: queue,
          priority: lowPriority.priority,
        ),
      );
      await broker.publish(
        highPriority,
        routing: RoutingInfo.queue(
          queue: queue,
          priority: highPriority.priority,
        ),
      );

      final iterator = StreamIterator(
        broker.consume(RoutingSubscription.singleQueue(queue), prefetch: 2),
      );
      expect(await iterator.moveNext(), isTrue);
      final first = iterator.current;
      expect(first.envelope.id, highPriority.id);
      await broker.ack(first);

      expect(await iterator.moveNext(), isTrue);
      final second = iterator.current;
      expect(second.envelope.id, lowPriority.id);
      await broker.ack(second);
      await iterator.cancel();

      await broker.purge(queue);
    } finally {
      await _safeCloseRedisBroker(broker);
    }
  });

  test('purge clears priority stream data', () async {
    final namespace = _uniqueNamespace();
    final broker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    try {
      final queue = _uniqueQueue();
      final highPriority = Envelope(
        name: 'integration.redis.high',
        args: const {'value': 'high'},
        queue: queue,
        priority: 7,
      );
      final lowPriority = Envelope(
        name: 'integration.redis.low',
        args: const {'value': 'low'},
        queue: queue,
        priority: 1,
      );

      await broker.publish(
        highPriority,
        routing: RoutingInfo.queue(
          queue: queue,
          priority: highPriority.priority,
        ),
      );
      await broker.publish(
        lowPriority,
        routing: RoutingInfo.queue(
          queue: queue,
          priority: lowPriority.priority,
        ),
      );

      expect(await broker.pendingCount(queue), 2);

      await broker.purge(queue);

      expect(await broker.pendingCount(queue), 0);

      final postPurge = Envelope(
        name: 'integration.redis.post_purge',
        args: const {'value': 'fresh'},
        queue: queue,
      );
      await broker.publish(postPurge);
      final iterator = StreamIterator(
        broker.consume(
          RoutingSubscription.singleQueue(queue),
          prefetch: 1,
          consumerName: 'purge-check-$queue',
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.envelope.id, postPurge.id);
      await broker.ack(iterator.current);
      await iterator.cancel();
    } finally {
      await _safeCloseRedisBroker(broker);
    }
  });

  test('subscription cancellation stops claim timers', () async {
    final namespace = _uniqueNamespace();
    final broker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
      claimInterval: const Duration(milliseconds: 50),
    );
    try {
      final queue = _uniqueQueue();
      final subscription = broker
          .consume(RoutingSubscription.singleQueue(queue), prefetch: 1)
          .listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(broker.activeClaimTimerCount, greaterThan(0));

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(broker.activeClaimTimerCount, 0);
    } finally {
      await _safeCloseRedisBroker(broker);
    }
  });

  test('Redis broadcast fan-out delivers to all subscribers', () async {
    final namespace = _uniqueNamespace();
    final publisher = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    final workerOneBroker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    final workerTwoBroker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
    );
    try {
      final queue = _uniqueQueue();
      final channel = '${queue}_broadcast';
      final subscription = RoutingSubscription(
        queues: [queue],
        broadcastChannels: [channel],
      );

      final workerOne = StreamQueue(
        workerOneBroker.consume(
          subscription,
          prefetch: 1,
          consumerGroup: 'group-$queue',
          consumerName: 'worker-one-$queue',
        ),
      );
      final workerTwo = StreamQueue(
        workerTwoBroker.consume(
          subscription,
          prefetch: 1,
          consumerGroup: 'group-$queue',
          consumerName: 'worker-two-$queue',
        ),
      );
      try {
        final broadcast = Envelope(
          name: 'integration.redis.broadcast',
          args: const {'value': 'fan-out'},
          queue: queue,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        await publisher.publish(
          broadcast,
          routing: RoutingInfo.broadcast(channel: channel),
        );

        final firstDelivery = await workerOne.next.timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
              fail('worker-one timed out waiting for broadcast message'),
        );
        final secondDelivery = await workerTwo.next.timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
              fail('worker-two timed out waiting for broadcast message'),
        );

        expect(firstDelivery.route.isBroadcast, isTrue);
        expect(secondDelivery.route.isBroadcast, isTrue);
        expect(firstDelivery.route.broadcastChannel, channel);
        expect(secondDelivery.route.broadcastChannel, channel);
        expect(firstDelivery.envelope.id, broadcast.id);
        expect(secondDelivery.envelope.id, broadcast.id);
        expect(firstDelivery.envelope.queue, channel);
        expect(secondDelivery.envelope.queue, channel);

        await workerOneBroker.ack(firstDelivery);
        await workerTwoBroker.ack(secondDelivery);

        await publisher.purge(queue);
      } finally {
        await workerOne.cancel(immediate: true);
        await workerTwo.cancel(immediate: true);
      }
    } finally {
      await _safeCloseRedisBroker(publisher);
    }
  });
}

String _uniqueQueue() =>
    'redis-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

var _counter = 0;

final _namespaceRandom = Random();

String _uniqueNamespace() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final suffix = _namespaceRandom.nextInt(1 << 32);
  return 'stem-test-$micros-$suffix';
}

Future<void> _safeCloseRedisBroker(RedisStreamsBroker broker) async {
  try {
    await runZonedGuarded(() => broker.close(), (Object _, StackTrace __) {});
  } catch (_) {}
}
