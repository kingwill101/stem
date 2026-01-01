// Basic durable workflow using in-memory broker/backend/store.
// Run with: dart run example/workflows/basic_in_memory.dart

import 'package:stem/stem.dart';

Future<void> main() async {
  final app = await StemWorkflowApp.inMemory(
    flows: [
      Flow(
        name: 'basic.hello',
        build: (flow) {
          flow.step('greet', (ctx) async => 'Hello Stem');
        },
      ),
    ],
  );

  final runId = await app.startWorkflow('basic.hello');
  final result = await app.waitForCompletion<String>(runId);
  print('Workflow $runId finished with result: ${result?.value}');

  await app.shutdown();
}
