import 'package:stem/stem.dart';
import 'package:test/test.dart';

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
}
