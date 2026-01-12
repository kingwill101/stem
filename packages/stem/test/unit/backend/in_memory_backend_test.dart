import 'dart:async';

import 'package:stem/src/backend/in_memory_backend.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/observability/heartbeat.dart';
import 'package:test/test.dart';

void main() {
  test('InMemoryResultBackend set/get/watch and expire', () async {
    final backend = InMemoryResultBackend(
      defaultTtl: const Duration(milliseconds: 50),
    );
    addTearDown(backend.dispose);

    final updates = <TaskStatus>[];
    final subscription = backend.watch('task-1').listen(updates.add);
    addTearDown(subscription.cancel);

    await backend.set('task-1', TaskState.queued);
    await backend.set('task-1', TaskState.running, attempt: 1);

    final status = await backend.get('task-1');
    expect(status?.state, TaskState.running);
    expect(updates, hasLength(2));

    await backend.expire('task-1', const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(await backend.get('task-1'), isNull);
  });

  test('InMemoryResultBackend group/chord operations', () async {
    final backend = InMemoryResultBackend(
      groupDefaultTtl: const Duration(milliseconds: 50),
    );
    addTearDown(backend.dispose);

    final descriptor = GroupDescriptor(
      id: 'group-1',
      expected: 2,
      meta: const {'type': 'chord'},
    );

    await backend.initGroup(descriptor);

    final status = TaskStatus(
      id: 'task-1',
      state: TaskState.succeeded,
      payload: {'ok': true},
      attempt: 0,
    );

    final group = await backend.addGroupResult('group-1', status);
    expect(group?.completed, 1);

    final fetched = await backend.getGroup('group-1');
    expect(fetched?.results['task-1']?.state, TaskState.succeeded);
    expect(fetched?.meta['type'], 'chord');

    final claimed = await backend.claimChord(
      'group-1',
      callbackTaskId: 'callback-task',
      dispatchedAt: DateTime.parse('2025-01-01T00:00:00Z'),
    );
    expect(claimed, isTrue);

    final claimedAgain = await backend.claimChord('group-1');
    expect(claimedAgain, isFalse);

    final updated = await backend.addGroupResult('group-1', status);
    expect(updated?.meta['stem.chord.claimed'], isTrue);
    expect(updated?.meta['stem.chord.callbackTaskId'], 'callback-task');
  });

  test('InMemoryResultBackend worker heartbeats expire', () async {
    final backend = InMemoryResultBackend(
      heartbeatTtl: const Duration(milliseconds: 5),
    );
    addTearDown(backend.dispose);

    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      timestamp: DateTime.now(),
      isolateCount: 1,
      inflight: 0,
      queues: [QueueHeartbeat(name: 'default', inflight: 0)],
    );

    await backend.setWorkerHeartbeat(heartbeat);
    expect(await backend.getWorkerHeartbeat('worker-1'), isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await backend.getWorkerHeartbeat('worker-1'), isNull);
    expect(await backend.listWorkerHeartbeats(), isEmpty);
  });
}
