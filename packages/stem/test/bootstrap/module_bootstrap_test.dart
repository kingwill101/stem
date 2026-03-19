import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('module bootstrap', () {
    test('StemApp.inMemory registers module tasks and infers queues', () async {
      final moduleTask = FunctionTaskHandler<String>(
        name: 'module.bootstrap.task',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(
        module: StemModule(tasks: [moduleTask]),
      );
      await app.start();
      try {
        expect(app.registry.resolve('module.bootstrap.task'), same(moduleTask));
        expect(app.worker.subscription.queues, ['priority']);

        final taskId = await app.stem.enqueue(
          'module.bootstrap.task',
          enqueueOptions: const TaskEnqueueOptions(queue: 'priority'),
        );
        final result = await app.stem.waitForTask<String>(
          taskId,
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
  });
}
