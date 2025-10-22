import 'dart:async';
import 'dart:io';

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
    final broker = await RedisStreamsBroker.connect(redisUrl);
    Future<void> safeClose(RedisStreamsBroker broker) async {
      try {
        await broker.close();
      } catch (_) {}
    }

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
        broker.consume(
          RoutingSubscription.singleQueue(queue),
          prefetch: 1,
        ),
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
      await broker.close();
    }
  });

  test('Redis broadcast fan-out delivers to all subscribers', () async {
    final namespace = 'stem-test-${DateTime.now().microsecondsSinceEpoch}';
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
    Future<void> safeClose(RedisStreamsBroker broker) async {
      try {
        await broker.close();
      } catch (_) {}
    }
    try {
      final queue = _uniqueQueue();
      final channel = '${queue}_broadcast';
      final subscription = RoutingSubscription(
        queues: [queue],
        broadcastChannels: [channel],
      );

      final futureOne = workerOneBroker
          .consume(
            subscription,
            prefetch: 1,
            consumerGroup: 'group-$queue',
            consumerName: 'worker-one-$queue',
          )
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        fail('worker-one timed out waiting for broadcast message');
      });
      final futureTwo = workerTwoBroker
          .consume(
            subscription,
            prefetch: 1,
            consumerGroup: 'group-$queue',
            consumerName: 'worker-two-$queue',
          )
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        fail('worker-two timed out waiting for broadcast message');
      });

      final broadcast = Envelope(
        name: 'integration.redis.broadcast',
        args: const {'value': 'fan-out'},
        queue: queue,
      );

      await publisher.publish(
        broadcast,
        routing: RoutingInfo.broadcast(channel: channel),
      );

      final results = await Future.wait([futureOne, futureTwo]);
      final firstDelivery = results[0];
      final secondDelivery = results[1];

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
      await safeClose(workerOneBroker);
      await safeClose(workerTwoBroker);
      await safeClose(publisher);
    }
  });
}

String _uniqueQueue() =>
    'redis-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

var _counter = 0;
