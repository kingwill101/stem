import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('shortcut allowWorkerAutoStart', () {
    test('StemApp can enqueue without starting the worker', () async {
      final app = await StemApp.inMemory(
        allowWorkerAutoStart: false,
        tasks: [
          FunctionTaskHandler<String>(
            name: 'shortcut.echo',
            entrypoint: (context, args) async => 'done',
          ),
        ],
      );

      try {
        final taskId = await app.enqueue('shortcut.echo');
        expect(app.isStarted, isFalse);

        final pending = await app.waitForTask<String>(
          taskId,
          timeout: const Duration(milliseconds: 10),
        );
        expect(pending, isNotNull);
        expect(pending!.timedOut, isTrue);
        expect(pending.status.state, TaskState.queued);

        await app.start();
        expect(app.isStarted, isTrue);

        final completed = await app.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 1),
        );
        expect(completed?.isSucceeded, isTrue);
        expect(completed?.value, 'done');
      } finally {
        await app.shutdown();
      }
    });

    test(
      'StemWorkflowApp can create runs without starting the worker',
      () async {
        final flow = Flow<String>(
          name: 'shortcut.workflow',
          build: (builder) {
            builder.step('done', (context) async => 'workflow-done');
          },
        );

        final app = await StemWorkflowApp.inMemory(
          flows: [flow],
          allowWorkerAutoStart: false,
        );

        try {
          final runId = await flow.start(app);
          expect(app.isRuntimeStarted, isTrue);
          expect(app.isWorkerStarted, isFalse);

          final pending = await app.waitForCompletion<String>(
            runId,
            timeout: const Duration(milliseconds: 10),
          );
          expect(pending, isNotNull);
          expect(pending!.timedOut, isTrue);
          expect(pending.status, WorkflowStatus.running);

          await app.startWorker();
          expect(app.isRuntimeStarted, isTrue);
          expect(app.isWorkerStarted, isTrue);
          expect(app.isStarted, isTrue);

          final completed = await flow.waitFor(
            app,
            runId,
            timeout: const Duration(seconds: 1),
          );
          expect(completed?.isCompleted, isTrue);
          expect(completed?.value, 'workflow-done');
        } finally {
          await app.shutdown();
        }
      },
    );
  });
}
