import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_redis/stem_redis.dart';
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

  String? contractNamespace;
  runBrokerContractTests(
    adapterName: 'Redis',
    factory: BrokerContractFactory(
      create: () async {
        final namespace = _uniqueNamespace();
        contractNamespace = namespace;
        return RedisStreamsBroker.connect(
          redisUrl,
          namespace: namespace,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          claimInterval: const Duration(milliseconds: 200),
          blockTime: const Duration(milliseconds: 100),
        );
      },
      dispose: (broker) async {
        if (broker is _NoCloseBroker) {
          return;
        }
        await _safeCloseRedisBroker(broker as RedisStreamsBroker);
      },
      additionalBrokerFactory: () async {
        final namespace = contractNamespace;
        if (namespace == null || namespace.isEmpty) {
          throw StateError(
            'Redis broadcast contract requires primary broker namespace.',
          );
        }
        final broker = await RedisStreamsBroker.connect(
          redisUrl,
          namespace: namespace,
          defaultVisibilityTimeout: const Duration(seconds: 1),
          claimInterval: const Duration(milliseconds: 200),
          blockTime: const Duration(milliseconds: 100),
        );
        return _NoCloseBroker(broker);
      },
    ),
    settings: const BrokerContractSettings(
      leaseExtension: Duration(seconds: 1),
      queueSettleDelay: Duration(milliseconds: 200),
      requeueTimeout: Duration(seconds: 10),
      capabilities: BrokerContractCapabilities(
        verifyBroadcastFanout: true,
      ),
    ),
  );

  test('namespace isolates queue data', () async {
    final namespaceA = _uniqueNamespace();
    final namespaceB = _uniqueNamespace();
    final brokerA = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespaceA,
      defaultVisibilityTimeout: const Duration(seconds: 1),
      blockTime: const Duration(milliseconds: 100),
    );
    final brokerB = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespaceB,
      defaultVisibilityTimeout: const Duration(seconds: 1),
      blockTime: const Duration(milliseconds: 100),
    );
    try {
      final queue = _uniqueQueue();
      final envelope = Envelope(
        name: 'integration.redis.namespace',
        args: const {'value': 1},
        queue: queue,
      );
      await brokerA.publish(envelope);

      final pendingA = await brokerA.pendingCount(queue);
      final pendingB = await brokerB.pendingCount(queue);

      expect(pendingA, 1);
      expect(pendingB, 0);
    } finally {
      await _safeCloseRedisBroker(brokerA);
      await _safeCloseRedisBroker(brokerB);
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
          .consume(RoutingSubscription.singleQueue(queue))
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

  test('concurrent consumers do not block publishes', () async {
    final namespace = _uniqueNamespace();
    const blockTime = Duration(milliseconds: 1500);
    final broker = await RedisStreamsBroker.connect(
      redisUrl,
      namespace: namespace,
      blockTime: blockTime,
    );
    StreamQueue<Delivery>? queueA;
    StreamQueue<Delivery>? queueB;
    try {
      final queueAName = '${_uniqueQueue()}-a';
      final queueBName = '${_uniqueQueue()}-b';
      queueA = StreamQueue(
        broker.consume(
          RoutingSubscription.singleQueue(queueAName),
          consumerName: 'consumer-a-$queueAName',
        ),
      );
      queueB = StreamQueue(
        broker.consume(
          RoutingSubscription.singleQueue(queueBName),
          consumerName: 'consumer-b-$queueBName',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final envelope = Envelope(
        name: 'integration.redis.concurrent',
        args: const {'value': 'ok'},
        queue: queueBName,
      );
      final publishWatch = Stopwatch()..start();
      await broker.publish(envelope);
      publishWatch.stop();

      expect(
        publishWatch.elapsedMilliseconds,
        lessThan(blockTime.inMilliseconds ~/ 2),
        reason: 'publish should not be delayed by another consumer',
      );

      final delivery = await queueB.next.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            fail('consumer-b timed out waiting for concurrent message'),
      );
      expect(delivery.envelope.id, envelope.id);
      await broker.ack(delivery);
    } finally {
      await queueA?.cancel(immediate: true);
      await queueB?.cancel(immediate: true);
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
          consumerGroup: 'group-$queue',
          consumerName: 'worker-one-$queue',
        ),
      );
      final workerTwo = StreamQueue(
        workerTwoBroker.consume(
          subscription,
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
    await runZonedGuarded(() => broker.close(), (Object _, StackTrace _) {});
  } on Object {
    // Ignore broker shutdown errors in cleanup.
  }
}

class _NoCloseBroker implements Broker {
  _NoCloseBroker(this._inner);

  final RedisStreamsBroker _inner;

  @override
  Future<void> ack(Delivery delivery) => _inner.ack(delivery);

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) => _inner.deadLetter(delivery, reason: reason, meta: meta);

  @override
  Future<void> extendLease(Delivery delivery, Duration by) =>
      _inner.extendLease(delivery, by);

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) =>
      _inner.getDeadLetter(queue, id);

  @override
  Future<int?> inflightCount(String queue) => _inner.inflightCount(queue);

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) => _inner.listDeadLetters(queue, limit: limit, offset: offset);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) =>
      _inner.nack(delivery, requeue: requeue);

  @override
  Future<int?> pendingCount(String queue) => _inner.pendingCount(queue);

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) =>
      _inner.publish(envelope, routing: routing);

  @override
  Future<void> purge(String queue) => _inner.purge(queue);

  @override
  Future<int> purgeDeadLetters(String queue, {DateTime? since, int? limit}) =>
      _inner.purgeDeadLetters(queue, since: since, limit: limit);

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) => _inner.replayDeadLetters(
    queue,
    limit: limit,
    since: since,
    delay: delay,
    dryRun: dryRun,
  );

  @override
  bool get supportsDelayed => _inner.supportsDelayed;

  @override
  bool get supportsPriority => _inner.supportsPriority;

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => _inner.consume(
    subscription,
    prefetch: prefetch,
    consumerGroup: consumerGroup,
    consumerName: consumerName,
  );

  @override
  Future<void> close() async {}
}
