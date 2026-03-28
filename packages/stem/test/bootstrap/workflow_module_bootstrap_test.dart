import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('workflow module bootstrap', () {
    test('StemWorkflowApp.inMemory merges plural modules', () async {
      final flow = Flow<String>(
        name: 'workflow.module.modules.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'flow-ok');
        },
      );
      final task = FunctionTaskHandler<String>(
        name: 'workflow.module.modules.task',
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final workflowApp = await StemWorkflowApp.inMemory(
        modules: [
          StemModule(flows: [flow]),
          StemModule(tasks: [task]),
        ],
      );
      try {
        expect(
          workflowApp.app.worker.subscription.queues,
          unorderedEquals(['workflow', 'default']),
        );

        await workflowApp.start();
        final runId = await workflowApp.startWorkflow(flow.definition.name);
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'flow-ok');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp.inMemory infers workflow and task queues', () async {
      final helperTask = FunctionTaskHandler<String>(
        name: 'workflow.module.queue-helper',
        entrypoint: (context, args) async => 'queued-ok',
        runInIsolate: false,
      );
      final helperDefinition = TaskDefinition.noArgs<String>(
        name: 'workflow.module.queue-helper',
      );
      final workflowApp = await StemWorkflowApp.inMemory(
        module: StemModule(tasks: [helperTask]),
      );
      try {
        expect(
          workflowApp.app.worker.subscription.queues,
          unorderedEquals(['workflow', 'default']),
        );

        await workflowApp.start();
        final result = await helperDefinition.enqueueAndWait(
          workflowApp,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'queued-ok');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'StemWorkflowApp.inMemory infers continuation and execution queues',
      () async {
        final helperTask = FunctionTaskHandler<String>(
          name: 'workflow.module.custom-queues-helper',
          entrypoint: (context, args) async => 'queued-ok',
          runInIsolate: false,
        );
        final workflowApp = await StemWorkflowApp.inMemory(
          module: StemModule(tasks: [helperTask]),
          continuationQueue: 'workflow-continue',
          executionQueue: 'workflow-step',
        );
        try {
          expect(
            workflowApp.app.worker.subscription.queues,
            unorderedEquals([
              'workflow',
              'workflow-continue',
              'workflow-step',
              'default',
            ]),
          );
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'StemClient.createWorkflowApp forwards continuation and execution '
      'queues',
      () async {
        final helperTask = FunctionTaskHandler<String>(
          name: 'workflow.module.client-custom-queues-helper',
          entrypoint: (context, args) async => 'queued-ok',
          runInIsolate: false,
        );
        final client = await StemClient.inMemory(
          module: StemModule(tasks: [helperTask]),
        );

        final workflowApp = await client.createWorkflowApp(
          continuationQueue: 'workflow-continue',
          executionQueue: 'workflow-step',
        );
        try {
          expect(
            workflowApp.app.worker.subscription.queues,
            unorderedEquals([
              'workflow',
              'workflow-continue',
              'workflow-step',
              'default',
            ]),
          );
        } finally {
          await workflowApp.shutdown();
          await client.close();
        }
      },
    );

    test(
      'StemWorkflowApp.fromClient falls back to client module for '
      'subscription inference',
      () async {
        final queuedTask = FunctionTaskHandler<String>(
          name: 'workflow.module.from-client-task',
          options: const TaskOptions(queue: 'priority'),
          entrypoint: (context, args) async => 'queued-ok',
          runInIsolate: false,
        );
        final client = await StemClient.inMemory(
          module: StemModule(tasks: [queuedTask]),
        );

        final workflowApp = await StemWorkflowApp.fromClient(client: client);
        try {
          expect(
            workflowApp.app.worker.subscription.queues,
            unorderedEquals(['workflow', 'priority']),
          );
        } finally {
          await workflowApp.shutdown();
          await client.close();
        }
      },
    );

    test(
      'explicit workflow subscription overrides inferred module queues',
      () async {
      final helperTask = FunctionTaskHandler<String>(
        name: 'workflow.module.explicit-subscription',
        entrypoint: (context, args) async => 'ignored',
        runInIsolate: false,
      );
      final workflowApp = await StemWorkflowApp.inMemory(
        module: StemModule(tasks: [helperTask]),
        workerConfig: StemWorkerConfig(
          queue: 'workflow',
          subscription: RoutingSubscription.singleQueue('workflow'),
        ),
      );
      try {
        expect(workflowApp.app.worker.subscription.queues, ['workflow']);
      } finally {
        await workflowApp.shutdown();
      }
      },
    );

    test(
      'StemApp.createWorkflowApp rejects missing continuation/execution '
      'coverage',
      () async {
        final helperTask = FunctionTaskHandler<String>(
          name: 'workflow.module.missing-custom-queues-helper',
          entrypoint: (context, args) async => 'queued-ok',
          runInIsolate: false,
        );
        final stemApp = await StemApp.inMemory(
          module: StemModule(tasks: [helperTask]),
          workerConfig: StemWorkerConfig(
            queue: 'workflow',
            subscription: RoutingSubscription(
              queues: ['workflow', 'default'],
            ),
          ),
        );

        try {
          await expectLater(
            () => stemApp.createWorkflowApp(
              continuationQueue: 'workflow-continue',
              executionQueue: 'workflow-step',
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('workflow-continue'),
                  contains('workflow-step'),
                ),
              ),
            ),
          );
        } finally {
          await stemApp.close();
        }
      },
    );

    test('registerModules registers flows and tasks together', () async {
      final flow = Flow<String>(
        name: 'workflow.module.register-modules.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'flow-ok');
        },
      );
      final task = FunctionTaskHandler<String>(
        name: 'workflow.module.register-modules.task',
        entrypoint: (context, args) async => 'task-ok',
        runInIsolate: false,
      );
      final taskDefinition = TaskDefinition.noArgs<String>(name: task.name);
      final workflowApp = await StemWorkflowApp.inMemory(
        workerConfig: StemWorkerConfig(
          queue: 'workflow',
          subscription: RoutingSubscription(
            queues: ['workflow', 'default'],
          ),
        ),
      );
      try {
        workflowApp.registerModules([
          StemModule(flows: [flow]),
          StemModule(tasks: [task]),
        ]);

        await workflowApp.start();
        final runId = await workflowApp.startWorkflow(flow.definition.name);
        final workflowResult = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        final taskResult = await taskDefinition.enqueueAndWait(
          workflowApp,
          timeout: const Duration(seconds: 2),
        );

        expect(workflowResult?.value, 'flow-ok');
        expect(taskResult?.value, 'task-ok');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('shutdown preserves a borrowed StemApp', () async {
      final hostTask = FunctionTaskHandler<String>(
        name: 'workflow.module.host-task',
        entrypoint: (context, args) async => 'host-ok',
        runInIsolate: false,
      );
      final flow = Flow<String>(
        name: 'workflow.module.borrowed-app',
        build: (builder) {
          builder.step('hello', (ctx) async => 'flow-ok');
        },
      );
      final hostApp = await StemApp.inMemory(
        tasks: [hostTask],
        workerConfig: StemWorkerConfig(
          subscription: RoutingSubscription(
            queues: ['default', 'workflow'],
          ),
        ),
      );
      final hostTaskDef = TaskDefinition.noArgs<String>(name: hostTask.name);

      await hostApp.start();
      final workflowApp = await hostApp.createWorkflowApp(flows: [flow]);
      try {
        await workflowApp.shutdown();

        expect(hostApp.isStarted, isTrue);

        final result = await hostTaskDef.enqueueAndWait(
          hostApp,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'host-ok');
      } finally {
        await hostApp.shutdown();
      }
    });
  });
}
