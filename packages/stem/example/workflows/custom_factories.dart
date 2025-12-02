// Combine adapters via factories (requires Redis running locally).
// Run with: dart run example/workflows/custom_factories.dart

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main() async {
  final app = await StemWorkflowApp.create(
    flows: [
      Flow(
        name: 'redis.workflow',
        build: (flow) {
          flow.step('greet', (ctx) async => 'Redis-backed workflow');
        },
      ),
    ],
    broker: redisBrokerFactory('redis://localhost:6379'),
    backend: redisResultBackendFactory('redis://localhost:6379/1'),
    storeFactory: redisWorkflowStoreFactory('redis://localhost:6379/2'),
  );

  try {
    final runId = await app.startWorkflow('redis.workflow');
    final result = await app.waitForCompletion<String>(runId);
    print('Workflow $runId finished with result: ${result?.value}');
  } finally {
    await app.shutdown();
  }
}
