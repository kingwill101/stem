import 'package:stem/stem.dart';

Future<void> main() async {
  final iterations = <int>[];

  final app = await StemWorkflowApp.inMemory(
    flows: [
      Flow(
        name: 'demo.versioned',
        build: (flow) {
          flow.step('repeat', (ctx) async {
            iterations.add(ctx.iteration);
            return 'iteration-${ctx.iteration}';
          }, autoVersion: true);

          flow.step('tail', (ctx) async => ctx.previousResult);
        },
      ),
    ],
  );

  final runId = await app.startWorkflow('demo.versioned');
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

  await app.close();
}
