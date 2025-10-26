import 'dart:async';
import 'dart:io';

import 'package:stem/src/backend/postgres_backend.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/observability/heartbeat.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres result backend integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres result backend integration tests.',
    );
    return;
  }

  late PostgresResultBackend backend;

  setUp(() async {
    backend = await PostgresResultBackend.connect(
      connectionString,
      applicationName: 'stem-postgres-backend-test',
      namespace: 'stem',
      defaultTtl: const Duration(seconds: 5),
      groupDefaultTtl: const Duration(seconds: 5),
      heartbeatTtl: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await backend.close();
  });

  test('set/get/watch/expire task statuses', () async {
    const taskId = 'task-123';
    final updates = backend.watch(taskId);
    final updateFuture = updates.first.timeout(const Duration(seconds: 5));

    final error = TaskError(
      type: 'TestError',
      message: 'boom',
      retryable: true,
      meta: const {'code': 42},
    );

    await backend.set(
      taskId,
      TaskState.succeeded,
      payload: const {'value': 'done'},
      error: error,
      attempt: 3,
      meta: const {
        'origin': 'test',
        'stem-signature': 'pg-sig',
        'stem-signature-key': 'pg-key',
      },
    );

    final status = await backend.get(taskId);
    expect(status, isNotNull);
    expect(status!.state, TaskState.succeeded);
    expect(status.payload, {'value': 'done'});
    expect(status.error?.type, 'TestError');
    expect(status.attempt, 3);
    expect(status.meta['origin'], 'test');
    expect(status.meta['stem-signature'], 'pg-sig');
    expect(status.meta['stem-signature-key'], 'pg-key');

    final streamed = await updateFuture;
    expect(streamed.id, taskId);
    expect(streamed.state, TaskState.succeeded);

    await backend.expire(taskId, const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await backend.get(taskId), isNull);
  });

  test('group lifecycle operations', () async {
    const groupId = 'group-1';
    final descriptor = GroupDescriptor(
      id: groupId,
      expected: 2,
      meta: const {'purpose': 'integration'},
      ttl: const Duration(seconds: 5),
    );

    await backend.initGroup(descriptor);

    final status = TaskStatus(
      id: 'child-1',
      state: TaskState.succeeded,
      payload: const {'value': 1},
      attempt: 1,
      meta: const {'meta': true},
    );

    final resultAfterFirst = await backend.addGroupResult(groupId, status);
    expect(resultAfterFirst, isNotNull);
    expect(resultAfterFirst!.results.length, 1);
    expect(resultAfterFirst.isComplete, isFalse);

    final resultAfterSecond = await backend.addGroupResult(
      groupId,
      TaskStatus(
        id: 'child-2',
        state: TaskState.succeeded,
        payload: const {'value': 2},
        attempt: 2,
        meta: const {'meta': true},
      ),
    );
    expect(resultAfterSecond, isNotNull);
    expect(resultAfterSecond!.results.length, 2);
    expect(resultAfterSecond.isComplete, isTrue);

    final fetched = await backend.getGroup(groupId);
    expect(fetched, isNotNull);
    expect(fetched!.results.length, 2);
    expect(fetched.meta['purpose'], 'integration');
  });

  test('worker heartbeats stored and listed', () async {
    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      namespace: 'stem',
      timestamp: DateTime.now(),
      isolateCount: 2,
      inflight: 1,
      queues: [QueueHeartbeat(name: 'default', inflight: 1)],
      extras: const {'key': 'value'},
    );

    await backend.setWorkerHeartbeat(heartbeat);

    final fetched = await backend.getWorkerHeartbeat('worker-1');
    expect(fetched, isNotNull);
    expect(fetched!.workerId, 'worker-1');
    expect(fetched.queues.single.name, 'default');
    expect(fetched.extras['key'], 'value');

    final heartbeats = await backend.listWorkerHeartbeats();
    expect(heartbeats, isNotEmpty);
    expect(heartbeats.first.workerId, 'worker-1');
  });

  test('addGroupResult returns null when group missing', () async {
    final status = TaskStatus(
      id: 'missing-child',
      state: TaskState.succeeded,
      payload: const {'value': 'no-group'},
      attempt: 1,
      meta: const {},
    );

    final result = await backend.addGroupResult('does-not-exist', status);
    expect(result, isNull);
  });
}
