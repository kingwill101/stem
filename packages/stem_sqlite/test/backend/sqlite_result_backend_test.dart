import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late SqliteResultBackend backend;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'stem_sqlite_result_backend_test',
    );
    dbFile = File('${tempDir.path}/backend.db');
    backend = await SqliteResultBackend.open(
      dbFile,
      defaultTtl: const Duration(seconds: 1),
      groupDefaultTtl: const Duration(seconds: 1),
      heartbeatTtl: const Duration(seconds: 1),
      cleanupInterval: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await backend.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  test('stores and retrieves task status', () async {
    await backend.set(
      'task-1',
      TaskState.succeeded,
      payload: {'value': 42},
      attempt: 1,
      meta: const {'origin': 'test'},
    );

    final status = await backend.get('task-1');
    expect(status, isNotNull);
    expect(status!.state, TaskState.succeeded);
    expect(status.payload, {'value': 42});
    expect(status.attempt, 1);
  });

  test('watches for task status updates', () async {
    final updates = <TaskStatus>[];
    final sub = backend.watch('task-2').listen(updates.add);
    addTearDown(sub.cancel);

    await backend.set('task-2', TaskState.running, attempt: 1, meta: const {});
    await backend.set(
      'task-2',
      TaskState.succeeded,
      attempt: 1,
      meta: const {},
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      updates.map((status) => status.state),
      containsAll([TaskState.running, TaskState.succeeded]),
    );
  });

  test('aggregates group results', () async {
    await backend.initGroup(
      GroupDescriptor(id: 'group-1', expected: 2, meta: const {}),
    );

    Future<void> store(String id, TaskState state) async {
      await backend.addGroupResult(
        'group-1',
        TaskStatus(id: id, state: state, attempt: 0),
      );
    }

    await store('task-a', TaskState.succeeded);
    await store('task-b', TaskState.failed);

    final status = await backend.getGroup('group-1');
    expect(status, isNotNull);
    expect(status!.completed, 2);
    expect(status.results['task-a']?.state, TaskState.succeeded);
    expect(status.results['task-b']?.state, TaskState.failed);
  });

  test('records worker heartbeats', () async {
    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      namespace: 'stem',
      timestamp: DateTime.now(),
      isolateCount: 2,
      inflight: 3,
      queues: [QueueHeartbeat(name: 'default', inflight: 2)],
    );
    await backend.setWorkerHeartbeat(heartbeat);

    final stored = await backend.getWorkerHeartbeat('worker-1');
    expect(stored, isNotNull);
    expect(stored!.workerId, 'worker-1');

    final listed = await backend.listWorkerHeartbeats();
    expect(listed, isNotEmpty);
  });

  test('cleanup removes expired task results', () async {
    await backend.set(
      'task-expire',
      TaskState.succeeded,
      ttl: const Duration(milliseconds: 50),
      meta: const {},
      attempt: 0,
    );

    await Future<void>.delayed(const Duration(milliseconds: 75));
    await backend.runCleanup();

    final status = await backend.get('task-expire');
    expect(status, isNull);
  });
}
