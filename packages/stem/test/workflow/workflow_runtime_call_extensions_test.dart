import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('runtime workflow start call dispatch', () {
    test(
      'buildStart() can be dispatched through WorkflowCaller',
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

          final runId = await workflowApp.runtime.startWorkflowCall(
            workflowRef.buildStart(params: const {'name': 'runtime'}),
          );
          final waited = await workflowRef.waitFor(
            workflowApp.runtime,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(waited?.value, 'hello runtime');

          final inlineCall = workflowRef.buildStart(
            params: const {'name': 'inline'},
          );
          final inlineRunId = await workflowApp.runtime.startWorkflowCall(
            inlineCall,
          );
          final oneShot = await workflowRef.waitFor(
            workflowApp.runtime,
            inlineRunId,
            timeout: const Duration(seconds: 2),
          );

          expect(oneShot?.value, 'hello inline');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'WorkflowRef direct helpers mirror WorkflowCaller startWorkflowCall',
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

          final runId = await workflowRef.start(
            workflowApp.runtime,
            params: const {'name': 'runtime'},
          );
          final waited = await workflowRef.waitFor(
            workflowApp.runtime,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(waited?.value, 'hello runtime');

          final oneShot = await workflowRef.startAndWait(
            workflowApp.runtime,
            params: const {'name': 'inline'},
            timeout: const Duration(seconds: 2),
          );

          expect(oneShot?.value, 'hello inline');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'named workflow start aliases mirror the direct workflow helpers',
      () async {
        final flow = Flow<String>(
          name: 'runtime.extension.named.flow',
          build: (builder) {
            builder.step('hello', (ctx) async {
              final name = ctx.params['name'] as String? ?? 'world';
              return 'hello $name';
            });
          },
        );
        final workflowRef = WorkflowRef<Map<String, Object?>, String>(
          name: 'runtime.extension.named.flow',
          encodeParams: (params) => params,
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          await workflowApp.start();

          final runId = await workflowRef.start(
            workflowApp.runtime,
            params: const {'name': 'runtime'},
          );
          final waited = await workflowRef.waitFor(
            workflowApp.runtime,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(waited?.value, 'hello runtime');

          final oneShot = await workflowRef.startAndWait(
            workflowApp.runtime,
            params: const {'name': 'inline'},
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
