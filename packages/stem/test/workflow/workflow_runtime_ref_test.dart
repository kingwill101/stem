import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('runtime workflow refs', () {
    test('start and wait helpers work directly with WorkflowRuntime', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'runtime.ref.flow',
        encodeParams: (params) => params,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final runId = await workflowApp.runtime.startWorkflowCall(
          workflowRef.call(const {'name': 'runtime'}),
        );
        final waited = await workflowApp.runtime.waitForWorkflowRef(
          runId,
          workflowRef,
          timeout: const Duration(seconds: 2),
        );

        expect(waited?.value, 'hello runtime');

        final inlineRunId = await workflowApp.runtime.startWorkflowRef(
          workflowRef,
          const {'name': 'inline'},
        );
        final oneShot = await workflowApp.runtime.waitForCompletion<String>(
          inlineRunId,
          timeout: const Duration(seconds: 2),
          decode: workflowRef.decode,
        );

        expect(oneShot?.value, 'hello inline');
      } finally {
        await workflowApp.shutdown();
      }
    });
  });
}
