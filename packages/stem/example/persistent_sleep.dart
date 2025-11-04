import 'package:stem/stem.dart';

/// Demonstrates persistent sleep semantics.
///
/// The workflow loops with `ctx.sleep` but no manual guard. Once the stored
/// wake timestamp elapses, the runtime skips re-suspending and the step
/// completes on the next invocation.
Future<void> main() async {
  var iterations = 0;

  final app = await StemWorkflowApp.inMemory(
    flows: [
      Flow(
        name: 'sleep.loop.workflow',
        build: (flow) {
          flow.step('loop', (ctx) async {
            iterations += 1;
            if (iterations == 1) {
              ctx.sleep(const Duration(milliseconds: 100));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      ),
    ],
  );

  final runId = await app.startWorkflow('sleep.loop.workflow');
  await app.runtime.executeRun(runId);

  // After the delay elapses, the runtime should resume without the step
  // manually inspecting resume data.
  await Future<void>.delayed(const Duration(milliseconds: 150));
  final due = await app.store.dueRuns(DateTime.now());
  for (final id in due) {
    final state = await app.store.get(id);
    await app.store.markResumed(id, data: state?.suspensionData);
    await app.runtime.executeRun(id);
  }

  final completed = await app.store.get(runId);
  print('Workflow completed with result: ${completed?.result}');
  await app.shutdown();
}
