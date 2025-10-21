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
    addTearDown(() => broker.close());

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
        broker.consume(RoutingSubscription.singleQueue(queue), prefetch: 1));
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
  });
}

String _uniqueQueue() =>
    'redis-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

var _counter = 0;
