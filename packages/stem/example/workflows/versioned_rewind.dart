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

  final app = await StemWorkflowApp.inMemory(
    flows: [versionedWorkflow],
  );

  final runId = await versionedWorkflow.startWith(app);
  await app.executeRun(runId);

  // Rewind and execute again to append a new iteration checkpoint.
  await app.rewindToCheckpoint(runId, 'repeat');
  await app.executeRun(runId);

  final checkpoints = await app.viewCheckpoints(runId);
  for (final checkpoint in checkpoints) {
    print('${checkpoint.checkpointName}: ${checkpoint.value}');
  }
  print('Iterations executed: $iterations');
  final completed = await versionedWorkflow.waitFor(app, runId);
  print('Final result: ${completed?.value}');

  await app.close();
}
