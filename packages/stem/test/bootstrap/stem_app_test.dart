import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemApp', () {
    test('inMemory executes tasks', () async {
      final handler = FunctionTaskHandler<void>(
        name: 'test.echo',
        entrypoint: (context, args) async => null,
        metadata: const TaskMetadata(idempotent: true),
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        await app.start();

        final taskId = await app.stem.enqueue('test.echo');
        final backend = app.backend as InMemoryResultBackend;
        final completed = await backend
            .watch(taskId)
            .firstWhere((status) => status.state == TaskState.succeeded)
            .timeout(const Duration(seconds: 1));
        expect(completed.state, TaskState.succeeded);
      } finally {
        await app.shutdown();
      }
    });
  });

  group('StemWorkflowApp', () {
    test('inMemory runs workflow to completion', () async {
      final flow = Flow(
        name: 'workflow.demo',
        build: (builder) {
          builder.step('hello', (ctx) async => 'hello world');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.demo');
        final run = await workflowApp
            .waitForCompletion(runId, timeout: const Duration(seconds: 1))
            .timeout(const Duration(seconds: 2));

        expect(run, isNotNull);
        expect(run!.status, WorkflowStatus.completed);
        expect(run.result, 'hello world');
      } finally {
        await workflowApp.shutdown();
      }
    });
  });
}
