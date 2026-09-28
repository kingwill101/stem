import 'dart:io';

import 'package:redis/redis.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['REDIS_URL'] ?? 'redis://127.0.0.1:56379/0';
  late Command command;
  late RedisWorkflowStore store;
  late FakeWorkflowClock clock;
  late String namespace;
  var counter = 0;

  setUp(() async {
    final connection = RedisConnection();
    addTearDown(connection.close);
    final uri = Uri.parse(url);
    final port = uri.hasPort ? uri.port : 6379;
    command = uri.scheme == 'rediss'
        ? await connection.connectWithSocket(
            await SecureSocket.connect(uri.host, port),
          )
        : await connection.connect(uri.host, port);
    if (uri.userInfo.isNotEmpty) {
      await command.send_object(['AUTH', uri.userInfo.split(':').last]);
    }
    if (uri.pathSegments.isNotEmpty) {
      await command.send_object(['SELECT', int.parse(uri.pathSegments.first)]);
    }
    namespace = 'review_${DateTime.now().microsecondsSinceEpoch}_${counter++}';
    addTearDown(() async {
      var cursor = '0';
      do {
        final result = await command.send_object([
          'SCAN',
          cursor,
          'MATCH',
          '$namespace:*',
          'COUNT',
          '100',
        ]) as List;
        cursor = result[0] as String;
        final keys = (result[1] as List).cast<String>();
        if (keys.isNotEmpty) await command.send_object(['DEL', ...keys]);
      } while (cursor != '0');
    });
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = await RedisWorkflowStore.connect(
      url,
      namespace: namespace,
      clock: clock,
    );
    addTearDown(store.close);
  });

  test('runtime IDs remain discoverable with delimited namespaces', () async {
    final scoped = await RedisWorkflowStore.connect(
      url,
      namespace: '$namespace:tenant[1]',
      clock: clock,
    );
    addTearDown(scoped.close);
    final broker = InMemoryBroker();
    addTearDown(broker.dispose);
    final backend = InMemoryResultBackend();
    addTearDown(backend.close);
    final registry = InMemoryTaskRegistry();
    final runtime = WorkflowRuntime(
      stem: Stem(broker: broker, backend: backend, registry: registry),
      store: scoped,
      eventBus: InMemoryEventBus(scoped),
      clock: clock,
    );
    addTearDown(runtime.dispose);
    registry.register(runtime.workflowRunnerHandler());
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'discovery',
        run: (script) => script.step('value', (_) => 'done'),
      ).definition,
    );
    final id = await runtime.startWorkflow('discovery');
    expect(id.startsWith('wf-'), isFalse);
    final custom = await scoped.createRun(
      workflow: 'discovery',
      params: const {},
      runId: 'tenant:42|custom',
    );
    // A checkpoint hash can contain run-like names; it is not another run.
    await scoped.saveStep(id, 'workflow', 'not-a-run');
    await scoped.saveStep(id, 'status', 'running');
    await scoped.saveStep(id, 'created_at', clock.now().toIso8601String());
    expect(
      (await scoped.listRuns()).map((run) => run.id),
      unorderedEquals([id, custom]),
    );
    expect(
      await scoped.listRunnableRuns(now: clock.now()),
      unorderedEquals([id, custom]),
    );
    final recovery = await runtime.recoverRunnableRuns();
    expect(recovery.enqueuedRunIds, unorderedEquals([id, custom]));
    expect(recovery.errors, isEmpty);
    await runtime.executeRun(id);
    expect((await scoped.get(id))!.status, WorkflowStatus.completed);

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'discovery.event',
        run: (script) => script.step(
          'wait',
          (step) => step.waitForEvent<Map<String, Object?>>(
            topic: 'discovery.event',
          ),
        ),
      ).definition,
    );
    final waiting = await runtime.startWorkflow('discovery.event');
    await runtime.executeRun(waiting);
    // Persist delivery without publishing the continuation, then recover it.
    await scoped.resolveWatchers('discovery.event', const {'ready': true});
    final resumed = await runtime.recoverRunnableRuns(
      workflows: {'discovery.event'},
    );
    expect(resumed.enqueuedRunIds, [waiting]);
    expect(resumed.errors, isEmpty);
    await runtime.executeRun(waiting);
    expect((await scoped.get(waiting))!.result, {'ready': true});
  });

  test('legacy watcher resolution preserves opaque JSON metadata', () async {
    // This VM-backed adapter must not round valid integers through Lua doubles.
    // ignore: avoid_js_rounded_ints
    const largeInteger = 9007199254740993;
    const opaque = <String, Object?>{
      'items': <Object?>[],
      'object': <String, Object?>{},
      'number': largeInteger,
      'null': null,
      'nested': <Object?>[
        <Object?>[],
        {'number': largeInteger},
      ],
    };
    final id = await store.createRun(workflow: 'legacy', params: {});
    await store.registerWatcher(
      id,
      'wait',
      'opaque.legacy',
      data: {'custom': opaque, 'payloadRaw': 'user metadata'},
    );
    final resolved = (await store.resolveWatchers(
      'opaque.legacy',
      opaque,
    )).single;
    expect(resolved.resumeData['payload'], opaque);
    expect(resolved.resumeData['custom'], opaque);
    expect(resolved.resumeData['payloadRaw'], 'user metadata');
    final persisted = (await store.get(id))!.suspensionData!;
    expect(persisted['payload'], opaque);
    expect(persisted['custom'], opaque);
    expect((persisted['payload']! as Map)['number'], isA<int>());
  });

  test('stale topic membership cannot resolve a replacement watcher', () async {
    final id = await store.createRun(workflow: 'legacy', params: {});
    await store.registerWatcher(id, 'old-step', 'old-topic');
    await store.registerWatcher(id, 'new-step', 'new-topic');
    await command.send_object([
      'ZADD',
      '$namespace:wf:watchers:topic:old-topic',
      0,
      id,
    ]);
    expect(
      await store.resolveWatchers('old-topic', const {'old': true}),
      isEmpty,
    );
    expect((await store.get(id))!.waitTopic, 'new-topic');
    expect(await store.listWatchers('new-topic'), hasLength(1));
  });

  test('stale membership does not consume a legacy resolution limit', () async {
    final id = await store.createRun(workflow: 'legacy', params: {});
    await store.registerWatcher(id, 'wait', 'topic');
    await command.send_object([
      'ZADD',
      '$namespace:wf:watchers:topic:topic',
      for (var i = 0; i < 9; i++) ...[i, 'stale-$i'],
    ]);
    final resolved = await store.resolveWatchers('topic', const {}, limit: 1);
    expect(resolved.map((item) => item.runId), [id]);
  });

  test('a full legacy page never reads the concurrent watcher index', () async {
    final id = await store.createRun(workflow: 'legacy', params: {});
    await store.registerWatcher(id, 'wait', 'topic');
    // A wrong-type sentinel makes any unnecessary ZRANGE fail, without relying
    // on timings or a benchmark to prove that the second query was skipped.
    await command.send_object([
      'SET',
      '$namespace:wf:concurrent:topic:topic',
      'must-not-read',
    ]);
    final watchers = await store.listWatchers('topic', limit: 1);
    expect(watchers.map((watcher) => watcher.runId), [id]);
  });

  test(
    'watcher paging finds valid entries beyond stale index members',
    () async {
      final id = await store.createRun(workflow: 'legacy', params: {});
      await store.registerWatcher(id, 'wait', 'topic');
      await command.send_object([
        'ZADD',
        '$namespace:wf:watchers:topic:topic',
        for (var i = 0; i < 9; i++) ...[i, 'stale-$i'],
      ]);
      expect(
        (await store.listWatchers('topic', limit: 1)).map((item) => item.runId),
        [id],
      );
    },
  );

  test(
    'due limits preserve concurrent timers until their atomic resume',
    () async {
      final legacy = await store.createRun(workflow: 'legacy', params: {});
      await store.suspendUntil(legacy, 'wait', clock.now());
      final id = await store.createRun(workflow: 'concurrent', params: {});
      final claim = (await store.claimRunExecution(id, ownerId: 'test-owner'))!;
      for (var i = 0; i < 2; i++) {
        await store.writeConcurrentStep(
          WorkflowConcurrentStepRecord(
            runId: id,
            invocationId: 'wait-$i',
            branch: '',
            stepName: 'wait-$i',
            stepIndex: i,
            iteration: 0,
            revision: 1,
            status: WorkflowConcurrentStepStatus.suspended,
            executionId: claim.executionId,
            updatedAt: clock.now(),
            suspensionData: {
              'type': 'sleep',
              'resumeAt': clock.now().toIso8601String(),
              'payload': true,
            },
          ),
          executionId: claim.executionId,
        );
      }
      await store.releaseRunExecution(id, executionId: claim.executionId);
      expect(await store.dueRuns(clock.now(), limit: 1), [legacy]);
      expect(await store.dueRuns(clock.now(), limit: 1), [id]);
      expect(await store.dueRuns(clock.now(), limit: 1), [id]);
      final resolved = await store.resumeDueConcurrentSteps(clock.now());
      expect(resolved, hasLength(2));
      expect(
        resolved.every(
          (item) => item.status == WorkflowConcurrentStepStatus.ready,
        ),
        isTrue,
      );
      expect(await store.dueRuns(clock.now(), limit: 1), isEmpty);
    },
  );
}
