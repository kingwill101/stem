// Basic durable workflow using in-memory broker/backend/store.
// Run with: dart run example/workflows/basic_in_memory.dart

import 'package:stem/stem.dart';

Future<void> main() async {
  final basicHello = Flow<String>(
    name: 'basic.hello',
    build: (flow) {
      flow.step('greet', (ctx) async => 'Hello Stem');
    },
  );
  final basicHelloRef = basicHello.ref0();

  final app = await StemWorkflowApp.inMemory(
    flows: [basicHello],
  );

  final runId = await basicHelloRef.startWith(app);
  final result = await basicHelloRef.waitFor(app, runId);
  print('Workflow $runId finished with result: ${result?.value}');

  await app.close();
}
