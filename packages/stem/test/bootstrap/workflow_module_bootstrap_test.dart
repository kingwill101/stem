import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('workflow module bootstrap', () {
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
  });
}
