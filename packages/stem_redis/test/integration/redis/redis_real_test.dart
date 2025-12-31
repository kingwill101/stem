import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

Future<bool> _canConnect(String uri) async {
  try {
    final broker = await RedisStreamsBroker.connect(uri);
    await broker.close();
    return true;
  } on Object {
    return false;
  }
}

void main() async {
  final uri =
      Platform.environment['STEM_TEST_REDIS_URL'] ??
      Platform.environment['REDIS_URL'] ??
      'redis://localhost:6379';
  final available = await _canConnect(uri);

  if (!available) {
    test(
      'redis integration skipped',
      () {},
      skip: 'Redis not available at $uri',
    );
    return;
  }

  runLockStoreContractTests(
    adapterName: 'Redis',
    factory: LockStoreContractFactory(
      create: () async => RedisLockStore.connect(
        uri,
        namespace:
            'stem-lock-contract-${DateTime.now().microsecondsSinceEpoch}',
      ),
      dispose: (store) => (store as RedisLockStore).close(),
    ),
    settings: const LockStoreContractSettings(
      initialTtl: Duration(milliseconds: 250),
      expiryBackoff: Duration(milliseconds: 250),
    ),
  );

  late RedisStreamsBroker broker;
  late RedisResultBackend backend;
  late RedisScheduleStore scheduleStore;
  late RedisLockStore lockStore;

  setUpAll(() async {
    broker = await RedisStreamsBroker.connect(uri);
    await broker.purge('integration');
    backend = await RedisResultBackend.connect(uri, namespace: 'stem-test');
    scheduleStore = await RedisScheduleStore.connect(
      uri,
      namespace: 'stem-test',
    );
    lockStore = await RedisLockStore.connect(uri, namespace: 'stem-test');
  });

  tearDownAll(() async {
    await lockStore.close();
    await backend.close();
    await scheduleStore.remove('integration-schedule');
    await broker.close();
  });

  test('publish and consume from Redis Streams', () async {
    final envelope = Envelope(
      name: 'integration.task',
      args: const {},
      queue: 'integration',
    );
    await broker.publish(envelope);

    final delivery = await broker
        .consume(
          RoutingSubscription.singleQueue('integration'),
          consumerName: 'integration-tester',
        )
        .first
        .timeout(const Duration(seconds: 5));

    expect(delivery.envelope.name, equals('integration.task'));
    await broker.ack(delivery);
    await broker.purge('integration');
  });

  test('RedisResultBackend persists and retrieves status', () async {
    const taskId = 'integration-task';
    await backend.set(
      taskId,
      TaskState.running,
      meta: const {
        'integration': true,
        'stem-signature': 'redis-sig',
        'stem-signature-key': 'redis-key',
      },
    );

    final status = await backend.get(taskId);
    expect(status, isNotNull);
    expect(status!.state, TaskState.running);
    expect(status.meta['integration'], isTrue);
    expect(status.meta['stem-signature'], 'redis-sig');
    expect(status.meta['stem-signature-key'], 'redis-key');

    await backend.set(
      taskId,
      TaskState.succeeded,
      payload: {'value': 1},
      attempt: 1,
    );
    final succeeded = await backend.get(taskId);
    expect(succeeded, isNotNull);
    expect(succeeded!.state, TaskState.succeeded);
    expect(succeeded.payload, equals({'value': 1}));

    await backend.expire(taskId, const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final expired = await backend.get(taskId);
    expect(expired, isNull);
  });

  test('RedisScheduleStore returns due entries once', () async {
    final entry = ScheduleEntry(
      id: 'integration-schedule',
      taskName: 'integration.task',
      queue: 'integration',
      spec: IntervalScheduleSpec(every: const Duration(milliseconds: 100)),
    );

    await scheduleStore.upsert(entry);
    final due = await scheduleStore.due(
      DateTime.now().add(const Duration(milliseconds: 150)),
    );
    expect(due, isNotEmpty);
    expect(due.first.taskName, equals('integration.task'));

    final snapshot = await scheduleStore.get('integration-schedule');
    expect(snapshot, isNotNull);
    expect(snapshot!.nextRunAt, isNotNull);

    // Subsequent call without upsert should be empty due to lock.
    final again = await scheduleStore.due(
      DateTime.now().add(const Duration(milliseconds: 200)),
    );
    expect(again, isEmpty);

    final executedAt = DateTime.now();
    await scheduleStore.markExecuted(
      'integration-schedule',
      scheduledFor: executedAt,
      executedAt: executedAt,
    );
    final latest = await scheduleStore.get(entry.id);
    expect(latest, isNotNull);
    expect(latest!.version, greaterThan(0));
    await scheduleStore.upsert(latest.copyWith(lastRunAt: DateTime.now()));
    await scheduleStore.remove(entry.id);
  });

  test('RedisLockStore acquires, renews, and releases locks', () async {
    final lock = await lockStore.acquire(
      'integration-lock',
      ttl: const Duration(milliseconds: 100),
    );
    expect(lock, isNotNull);

    final second = await lockStore.acquire('integration-lock');
    expect(second, isNull, reason: 'second acquisition should fail while held');

    final renewed = await lock!.renew(const Duration(milliseconds: 200));
    expect(renewed, isTrue);

    await lock.release();

    final afterRelease = await lockStore.acquire('integration-lock');
    expect(afterRelease, isNotNull);
    await afterRelease!.release();
  });

  test('UniqueTaskCoordinator deduplicates with RedisLockStore', () async {
    final coordinator = UniqueTaskCoordinator(
      lockStore: lockStore,
      namespace: 'stem-test:unique:${DateTime.now().microsecondsSinceEpoch}',
      defaultTtl: const Duration(seconds: 1),
    );
    const options = TaskOptions(unique: true, uniqueFor: Duration(seconds: 1));

    final envelope = Envelope(
      name: 'integration.unique',
      args: const {'id': 1},
      queue: 'integration',
    );
    final first = await coordinator.acquire(
      envelope: envelope,
      options: options,
    );
    expect(first.isAcquired, isTrue);

    final duplicate = Envelope(
      name: 'integration.unique',
      args: const {'id': 1},
      queue: 'integration',
    );
    final second = await coordinator.acquire(
      envelope: duplicate,
      options: options,
    );
    expect(second.isAcquired, isFalse);
    expect(second.existingTaskId, equals(envelope.id));

    final released = await coordinator.release(first.uniqueKey, first.owner);
    expect(released, isTrue);

    final afterRelease = Envelope(
      name: 'integration.unique',
      args: const {'id': 1},
      queue: 'integration',
    );
    final third = await coordinator.acquire(
      envelope: afterRelease,
      options: options,
    );
    expect(third.isAcquired, isTrue);

    await coordinator.release(third.uniqueKey, third.owner);
  });
}
