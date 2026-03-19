import 'package:stem/stem.dart';

Future<void> main() async {
  final iterations = <int>[];
  final versionedWorkflow = Flow<String>(
    name: 'demo.versioned',
    build: (flow) {
      flow.step('repeat', (ctx) async {
        iterations.add(ctx.iteration);
        return 'iteration-${ctx.iteration}';
      }, autoVersion: true);

      flow.step('tail', (ctx) async => ctx.previousResult);
    },
  );
  final versionedWorkflowRef = versionedWorkflow.ref0();

  final app = await StemWorkflowApp.inMemory(
    flows: [versionedWorkflow],
  );

  final runId = await versionedWorkflowRef.startWithApp(app);
  await app.runtime.executeRun(runId);

  // Rewind and execute again to append a new iteration checkpoint.
  await app.store.rewindToStep(runId, 'repeat');
  await app.store.markRunning(runId);
  await app.runtime.executeRun(runId);

  final entries = await app.store.listSteps(runId);
  for (final entry in entries) {
    print('${entry.name}: ${entry.value}');
  }
  print('Iterations executed: $iterations');
  final completed = await versionedWorkflowRef.waitFor(app, runId);
  print('Final result: ${completed?.value}');

  await app.close();
}
