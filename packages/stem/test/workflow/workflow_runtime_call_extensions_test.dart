import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('runtime workflow call extensions', () {
    test(
      'startWith/startAndWaitWithRuntime and waitForWithRuntime use typed workflow refs',
      () async {
        final flow = Flow<String>(
          name: 'runtime.extension.flow',
          build: (builder) {
            builder.step('hello', (ctx) async {
              final name = ctx.params['name'] as String? ?? 'world';
              return 'hello $name';
            });
          },
        );
        final workflowRef = WorkflowRef<Map<String, Object?>, String>(
          name: 'runtime.extension.flow',
          encodeParams: (params) => params,
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          await workflowApp.start();

          final runId = await workflowRef
              .call(const {'name': 'runtime'})
              .startWith(workflowApp.runtime);
          final waited = await workflowRef.waitForWithRuntime(
            workflowApp.runtime,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(waited?.value, 'hello runtime');

          final oneShot = await workflowRef
              .call(const {'name': 'inline'})
              .startAndWaitWithRuntime(
                workflowApp.runtime,
                timeout: const Duration(seconds: 2),
              );

          expect(oneShot?.value, 'hello inline');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'WorkflowRef direct helpers mirror WorkflowStartCall dispatch',
      () async {
      final flow = Flow<String>(
        name: 'runtime.extension.direct.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'runtime.extension.direct.flow',
        encodeParams: (params) => params,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final runId = await workflowRef.startWithRuntime(
          workflowApp.runtime,
          const {'name': 'runtime'},
        );
        final waited = await workflowRef.waitForWithRuntime(
          workflowApp.runtime,
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(waited?.value, 'hello runtime');

        final oneShot = await workflowRef.startAndWaitWithRuntime(
          workflowApp.runtime,
          const {'name': 'inline'},
          timeout: const Duration(seconds: 2),
        );

        expect(oneShot?.value, 'hello inline');
      } finally {
        await workflowApp.shutdown();
      }
      },
    );
  });
}
