import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemModule.merge', () {
    test('combine returns null, a single module, or a merged module', () {
      final taskA = FunctionTaskHandler<String>(
        name: 'module.combine.task.a',
        entrypoint: (context, args) async => 'a',
        runInIsolate: false,
      );
      final taskB = FunctionTaskHandler<String>(
        name: 'module.combine.task.b',
        entrypoint: (context, args) async => 'b',
        runInIsolate: false,
      );
      final moduleA = StemModule(tasks: [taskA]);
      final moduleB = StemModule(tasks: [taskB]);

      expect(StemModule.combine(), isNull);
      expect(StemModule.combine(module: moduleA), same(moduleA));
      expect(
        StemModule.combine(modules: [moduleA, moduleB])?.tasks,
        [taskA, taskB],
      );
    });

    test('combines distinct task and workflow definitions', () async {
      final taskA = FunctionTaskHandler<String>(
        name: 'module.merge.task.a',
        entrypoint: (context, args) async => 'a',
        runInIsolate: false,
      );
      final taskB = FunctionTaskHandler<String>(
        name: 'module.merge.task.b',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'b',
        runInIsolate: false,
      );
      final flow = Flow<String>(
        name: 'module.merge.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'ok');
        },
      );
      final merged = StemModule.merge([
        StemModule(tasks: [taskA]),
        StemModule(flows: [flow], tasks: [taskB]),
      ]);

      expect(merged.tasks, [taskA, taskB]);
      expect(
        merged.workflowDefinitions.map((definition) => definition.name),
        ['module.merge.flow'],
      );
      expect(merged.workflowManifest.map((entry) => entry.name), [
        'module.merge.flow',
      ]);

      final app = await StemWorkflowApp.inMemory(module: merged);
      try {
        await app.start();

        final runId = await app.startWorkflow('module.merge.flow');
        final flowResult = await app.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(flowResult?.value, 'ok');
      } finally {
        await app.close();
      }
    });

    test('deduplicates identical modules and manifest entries', () {
      final flow = Flow<String>(
        name: 'module.merge.duplicate.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'ok');
        },
      );
      final task = FunctionTaskHandler<String>(
        name: 'module.merge.duplicate.task',
        entrypoint: (context, args) async => 'ok',
        runInIsolate: false,
      );
      final module = StemModule(flows: [flow], tasks: [task]);

      final merged = StemModule.merge([module, module]);

      expect(merged.tasks, [task]);
      expect(
        merged.workflowDefinitions.map((definition) => definition.name),
        ['module.merge.duplicate.flow'],
      );
      expect(merged.workflowManifest.map((entry) => entry.name), [
        'module.merge.duplicate.flow',
      ]);
    });

    test('fails fast on conflicting task or workflow names', () {
      final taskA = FunctionTaskHandler<String>(
        name: 'module.merge.conflict.task',
        entrypoint: (context, args) async => 'a',
        runInIsolate: false,
      );
      final taskB = FunctionTaskHandler<String>(
        name: 'module.merge.conflict.task',
        entrypoint: (context, args) async => 'b',
        runInIsolate: false,
      );
      final flowA = Flow<String>(
        name: 'module.merge.conflict.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'a');
        },
      );
      final flowB = Flow<String>(
        name: 'module.merge.conflict.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'b');
        },
      );

      expect(
        () => StemModule.merge([
          StemModule(tasks: [taskA]),
          StemModule(tasks: [taskB]),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('module.merge.conflict.task'),
          ),
        ),
      );
      expect(
        () => StemModule.merge([
          StemModule(flows: [flowA]),
          StemModule(flows: [flowB]),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('module.merge.conflict.workflow'),
          ),
        ),
      );
    });
  });

  group('module bootstrap', () {
    test('StemApp.inMemory registers module tasks and infers queues', () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'module.bootstrap.task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final moduleDefinition = TaskDefinition.noArgs<String>(
        name: 'module.bootstrap.task',
        defaultOptions: const TaskOptions(queue: 'priority'),
      );

      final app = await StemApp.inMemory(
        module: StemModule(tasks: [moduleTask]),
      );
      await app.start();
      try {
        expect(app.registry.resolve('module.bootstrap.task'), same(moduleTask));
        expect(app.worker.subscription.queues, ['priority']);

        final result = await moduleDefinition.enqueueAndWait(
          app,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'task-ok');
      } finally {
        await app.close();
      }
    });

    test('StemClient.createApp reuses its default module', () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'module.client.task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final client = await StemClient.inMemory(
        module: StemModule(tasks: [moduleTask]),
      );

      final app = await client.createApp();
      await app.start();
      try {
        expect(app.registry.resolve('module.client.task'), same(moduleTask));
        expect(app.worker.subscription.queues, ['priority']);
      } finally {
        await app.close();
        await client.close();
      }
    });

    test('StemApp.inMemory merges plural modules during bootstrap', () async {
      final taskA = FunctionTaskHandler<String>(
        name: 'module.bootstrap.modules.task.a',
        entrypoint: (context, args) async => 'a',
        runInIsolate: false,
      );
      final taskB = FunctionTaskHandler<String>(
        name: 'module.bootstrap.modules.task.b',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'b',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(
        modules: [
          StemModule(tasks: [taskA]),
          StemModule(tasks: [taskB]),
        ],
      );
      await app.start();
      try {
        expect(app.registry.resolve(taskA.name), same(taskA));
        expect(app.registry.resolve(taskB.name), same(taskB));
        expect(
          app.worker.subscription.queues,
          unorderedEquals(['default', 'priority']),
        );
      } finally {
        await app.close();
      }
    });

    test('StemClient.createWorkflowApp reuses its default module', () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'module.client.workflow-task',
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final moduleFlow = Flow<String>(
        name: 'module.client.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'module-ok');
        },
      );
      final client = await StemClient.inMemory(
        module: StemModule(flows: [moduleFlow], tasks: [moduleTask]),
      );

      final app = await client.createWorkflowApp();
      await app.start();
      try {
        expect(
          app.app.registry.resolve('module.client.workflow-task'),
          same(moduleTask),
        );

        final runId = await app.startWorkflow('module.client.workflow');
        final result = await app.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'module-ok');
      } finally {
        await app.close();
        await client.close();
      }
    });

    test('StemApp.createWorkflowApp reuses its default module', () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'module.app.workflow-task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final moduleFlow = Flow<String>(
        name: 'module.app.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'module-ok');
        },
      );
      final stemApp = await StemApp.inMemory(
        module: StemModule(flows: [moduleFlow], tasks: [moduleTask]),
        workerConfig: StemWorkerConfig(
          queue: 'workflow',
          subscription: RoutingSubscription(
            queues: ['workflow', 'priority'],
          ),
        ),
      );

      final workflowApp = await stemApp.createWorkflowApp();
      await workflowApp.start();
      try {
        expect(
          workflowApp.app.registry.resolve('module.app.workflow-task'),
          same(moduleTask),
        );

        final runId = await workflowApp.startWorkflow('module.app.workflow');
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'module-ok');
      } finally {
        await workflowApp.close();
      }
    });

    test('StemApp.createWorkflowApp registers plural modules', () async {
      final flow = Flow<String>(
        name: 'module.app.modules.workflow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'module-ok');
        },
      );
      final task = FunctionTaskHandler<String>(
        name: 'module.app.modules.task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final stemApp = await StemApp.inMemory(
        workerConfig: StemWorkerConfig(
          queue: 'workflow',
          subscription: RoutingSubscription(
            queues: ['workflow', 'priority'],
          ),
        ),
      );

      final workflowApp = await stemApp.createWorkflowApp(
        modules: [
          StemModule(flows: [flow]),
          StemModule(tasks: [task]),
        ],
      );
      await workflowApp.start();
      try {
        expect(workflowApp.app.registry.resolve(task.name), same(task));

        final runId = await workflowApp.startWorkflow(flow.definition.name);
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'module-ok');
      } finally {
        await workflowApp.close();
      }
    });

    test(
      'StemWorkflowApp.create rejects reused StemApp without workflow queue '
      'coverage',
      () async {
        final moduleFlow = Flow<String>(
          name: 'module.app.missing-workflow-queue',
          build: (builder) {
            builder.step('hello', (ctx) async => 'module-ok');
          },
        );
        final stemApp = await StemApp.inMemory(
          module: StemModule(flows: [moduleFlow]),
        );

        try {
          await expectLater(
            stemApp.createWorkflowApp,
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('reused StemApp worker'),
              ),
            ),
          );
        } finally {
          await stemApp.close();
        }
      },
    );
  });
}
