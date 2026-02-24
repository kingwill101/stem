import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'test_store_adapter.dart';

void main() {
  test('StemClient inMemory runs workflow end-to-end', () async {
    final client = await StemClient.inMemory();
    final flow = Flow<String>(
      name: 'client.workflow',
      build: (builder) {
        builder.step('hello', (ctx) async => 'ok');
      },
    );

    final app = await client.createWorkflowApp(flows: [flow]);
    await app.start();

    final runId = await app.startWorkflow('client.workflow');
    final result = await app.waitForCompletion<String>(
      runId,
      timeout: const Duration(seconds: 2),
    );

    expect(result?.value, 'ok');

    await app.close();
    await client.close();
  });

  test('StemClient fromUrl resolves adapter-backed broker/backend', () async {
    final handler = FunctionTaskHandler<String>(
      name: 'client.from-url',
      entrypoint: (context, args) async => 'ok',
    );
    final client = await StemClient.fromUrl(
      'test://localhost',
      adapters: [
        TestStoreAdapter(
          scheme: 'test',
          adapterName: 'client-test-adapter',
          broker: StemBrokerFactory(create: () async => InMemoryBroker()),
          backend: StemBackendFactory(
            create: () async => InMemoryResultBackend(),
          ),
        ),
      ],
      tasks: [handler],
    );

    final worker = await client.createWorker();
    await worker.start();
    try {
      final taskId = await client.stem.enqueue('client.from-url');
      final result = await client.stem.waitForTask<String>(
        taskId,
        timeout: const Duration(seconds: 2),
      );
      expect(result?.value, 'ok');
    } finally {
      await worker.shutdown();
      await client.close();
    }
  });
}
