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
      final workflowApp = await StemWorkflowApp.inMemory(
        module: StemModule(tasks: [helperTask]),
      );
      try {
        expect(
          workflowApp.app.worker.subscription.queues,
          unorderedEquals(['workflow', 'default']),
        );

        await workflowApp.start();
        final taskId = await workflowApp.app.stem.enqueue(
          'workflow.module.queue-helper',
        );
        final result = await workflowApp.app.stem.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'queued-ok');
      } finally {
        await workflowApp.shutdown();
      }
    });

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
  });
}
