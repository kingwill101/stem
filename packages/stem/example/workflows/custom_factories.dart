// Combine adapters via factories (requires Redis running locally).
// Run with: dart run example/workflows/custom_factories.dart

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main() async {
  final redisWorkflow = Flow<String>(
    name: 'redis.workflow',
    build: (flow) {
      flow.step('greet', (ctx) async => 'Redis-backed workflow');
    },
  );
  final redisWorkflowRef = redisWorkflow.ref<Map<String, Object?>>(
    encodeParams: (params) => params,
  );
  final app = await StemWorkflowApp.fromUrl(
    'redis://localhost:6379',
    adapters: const [StemRedisAdapter()],
    overrides: const StemStoreOverrides(
      backend: 'redis://localhost:6379/1',
      workflow: 'redis://localhost:6379/2',
    ),
    flows: [redisWorkflow],
  );

  try {
    final runId = await redisWorkflowRef.call(const {}).startWithApp(app);
    final result = await redisWorkflowRef.waitFor(app, runId);
    print('Workflow $runId finished with result: ${result?.value}');
  } finally {
    await app.close();
  }
}
