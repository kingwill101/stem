import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'test_store_adapter.dart';

void main() {
  test('StemClient inMemory runs workflow end-to-end', () async {
    final client = await StemClient.inMemory();
    final flow = Flow<String>(
      name: 'client.workflow',
      build: (builder) {
        builder.step('hello', (ctx) async => 'ok');
      },
    );

    final app = await client.createWorkflowApp(flows: [flow]);
    await app.start();

    final runId = await app.startWorkflow('client.workflow');
    final result = await app.waitForCompletion<String>(
      runId,
      timeout: const Duration(seconds: 2),
    );

    expect(result?.value, 'ok');

    await app.close();
    await client.close();
  });

  test('StemClient createWorkflowApp registers module definitions', () async {
    final client = await StemClient.inMemory();
    final moduleTask = FunctionTaskHandler<String>(
      name: 'client.module.task',
      entrypoint: (context, args) async => 'task-ok',
      runInIsolate: false,
    );
    final moduleFlow = Flow<String>(
      name: 'client.module.workflow',
      build: (builder) {
        builder.step('hello', (ctx) async => 'module-ok');
      },
    );
    final module = StemModule(flows: [moduleFlow], tasks: [moduleTask]);

    final app = await client.createWorkflowApp(module: module);
    await app.start();

    expect(app.app.registry.resolve('client.module.task'), same(moduleTask));

    final runId = await app.startWorkflow('client.module.workflow');
    final result = await app.waitForCompletion<String>(
      runId,
      timeout: const Duration(seconds: 2),
    );

    expect(result?.value, 'module-ok');

    await app.close();
    await client.close();
  });

  test(
    'StemClient remembers its default module for createApp',
    () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'client.default-module.app-task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final client = await StemClient.inMemory(
        module: StemModule(tasks: [moduleTask]),
      );

      final app = await client.createApp();
      await app.start();

      expect(
        app.registry.resolve('client.default-module.app-task'),
        same(moduleTask),
      );
      expect(app.worker.subscription.queues, ['priority']);

      final taskId = await app.stem.enqueue(
        'client.default-module.app-task',
        enqueueOptions: const TaskEnqueueOptions(queue: 'priority'),
      );
      final result = await app.stem.waitForTask<String>(
        taskId,
        timeout: const Duration(seconds: 2),
      );

      expect(result?.value, 'task-ok');

      await app.close();
      await client.close();
    },
  );

  test(
    'StemClient createApp registers module tasks and infers queues',
    () async {
      final client = await StemClient.inMemory();
      final moduleTask = FunctionTaskHandler<String>(
        name: 'client.module.app-task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );

      final app = await client.createApp(
        module: StemModule(tasks: [moduleTask]),
      );
      await app.start();

      expect(app.registry.resolve('client.module.app-task'), same(moduleTask));
      expect(app.worker.subscription.queues, ['priority']);

      final taskId = await app.stem.enqueue(
        'client.module.app-task',
        enqueueOptions: const TaskEnqueueOptions(queue: 'priority'),
      );
      final result = await app.stem.waitForTask<String>(
        taskId,
        timeout: const Duration(seconds: 2),
      );

      expect(result?.value, 'task-ok');

      await app.close();
      await client.close();
    },
  );

  test(
    'StemClient createWorkflowApp infers module task queue subscriptions',
    () async {
      final client = await StemClient.inMemory();
      final moduleTask = FunctionTaskHandler<String>(
        name: 'client.module.queued-task',
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final taskDefinition = TaskDefinition.noArgs<String>(
        name: 'client.module.queued-task',
      );
      final app = await client.createWorkflowApp(
        module: StemModule(tasks: [moduleTask]),
      );

      expect(
        app.app.worker.subscription.queues,
        unorderedEquals(['workflow', 'default']),
      );

      await app.start();
      final result = await taskDefinition.enqueueAndWait(
        app,
        timeout: const Duration(seconds: 2),
      );

      expect(result?.value, 'task-ok');

      await app.close();
      await client.close();
    },
  );

  test(
    'StemClient remembers its default module for createWorkflowApp',
    () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'client.default-module.workflow-task',
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final moduleFlow = Flow<String>(
        name: 'client.default-module.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'module-ok');
        },
      );
      final client = await StemClient.inMemory(
        module: StemModule(flows: [moduleFlow], tasks: [moduleTask]),
      );

      final app = await client.createWorkflowApp();
      await app.start();

      expect(
        app.app.registry.resolve('client.default-module.workflow-task'),
        same(moduleTask),
      );
      expect(
        app.app.worker.subscription.queues,
        unorderedEquals(['workflow', 'default']),
      );

      final runId = await app.startWorkflow('client.default-module.workflow');
      final result = await app.waitForCompletion<String>(
        runId,
        timeout: const Duration(seconds: 2),
      );

      expect(result?.value, 'module-ok');

      await app.close();
      await client.close();
    },
  );

  test('StemClient workflow app supports typed workflow refs', () async {
    final client = await StemClient.inMemory();
    final flow = Flow<String>(
      name: 'client.workflow.ref',
      build: (builder) {
        builder.step('hello', (ctx) async {
          final name = ctx.params['name'] as String? ?? 'world';
          return 'ok:$name';
        });
      },
    );
    final workflowRef = WorkflowRef<Map<String, Object?>, String>(
      name: 'client.workflow.ref',
      encodeParams: (params) => params,
    );

    final app = await client.createWorkflowApp(flows: [flow]);
    await app.start();

    final runId = await app.startWorkflowCall(
      workflowRef.call(const {'name': 'ref'}),
    );
    final result = await app.waitForWorkflowRef(
      runId,
      workflowRef,
      timeout: const Duration(seconds: 2),
    );

    expect(result?.value, 'ok:ref');

    await app.close();
    await client.close();
  });

  test('StemClient workflow app supports startAndWaitWith', () async {
    final client = await StemClient.inMemory();
    final flow = Flow<String>(
      name: 'client.workflow.start-and-wait',
      build: (builder) {
        builder.step('hello', (ctx) async {
          final name = ctx.params['name'] as String? ?? 'world';
          return 'ok:$name';
        });
      },
    );
    final workflowRef = WorkflowRef<Map<String, Object?>, String>(
      name: 'client.workflow.start-and-wait',
      encodeParams: (params) => params,
    );

    final app = await client.createWorkflowApp(flows: [flow]);
    await app.start();

    final result = await workflowRef
        .call(
          const {'name': 'one-shot'},
        )
        .startAndWaitWith(app, timeout: const Duration(seconds: 2));

    expect(result?.value, 'ok:one-shot');

    await app.close();
    await client.close();
  });

  test('StemClient fromUrl resolves adapter-backed broker/backend', () async {
    final handler = FunctionTaskHandler<String>(
      name: 'client.from-url',
      entrypoint: (context, args) async => 'ok',
    );
    final definition = TaskDefinition.noArgs<String>(name: 'client.from-url');
    final client = await StemClient.fromUrl(
      'test://localhost',
      adapters: [
        TestStoreAdapter(
          scheme: 'test',
          adapterName: 'client-test-adapter',
          broker: StemBrokerFactory(create: () async => InMemoryBroker()),
          backend: StemBackendFactory(
            create: () async => InMemoryResultBackend(),
          ),
        ),
      ],
      tasks: [handler],
    );

    final worker = await client.createWorker();
    await worker.start();
    try {
      final result = await definition.enqueueAndWait(
        client,
        timeout: const Duration(seconds: 2),
      );
      expect(result?.value, 'ok');
    } finally {
      await worker.shutdown();
      await client.close();
    }
  });
}
