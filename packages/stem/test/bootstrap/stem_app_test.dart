import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemApp', () {
    test('inMemory executes tasks', () async {
      final handler = FunctionTaskHandler<void>(
        name: 'test.echo',
        entrypoint: (context, args) async => null,
        metadata: const TaskMetadata(idempotent: true),
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        await app.start();

        final taskId = await app.stem.enqueue('test.echo');
        final backend = app.backend as InMemoryResultBackend;
        final completed = await backend
            .watch(taskId)
            .firstWhere((status) => status.state == TaskState.succeeded)
            .timeout(const Duration(seconds: 1));
        expect(completed.state, TaskState.succeeded);
      } finally {
        await app.shutdown();
      }
    });
  });

  group('StemWorkflowApp', () {
    test('inMemory runs workflow to completion', () async {
      final flow = Flow(
        name: 'workflow.demo',
        build: (builder) {
          builder.step('hello', (ctx) async => 'hello world');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.demo');
        final run = await workflowApp
            .waitForCompletion<String>(
              runId,
              timeout: const Duration(seconds: 1),
            )
            .timeout(const Duration(seconds: 2));

        expect(run, isNotNull);
        expect(run!.status, WorkflowStatus.completed);
        expect(run.value, 'hello world');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('waitForCompletion decodes custom types on success', () async {
      final flow = Flow<Map<String, Object?>>(
        name: 'workflow.typed',
        build: (builder) {
          builder.step('payload', (ctx) async => {'foo': 'bar'});
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.typed');
        final run = await workflowApp.waitForCompletion<_DemoPayload>(
          runId,
          decode: (payload) =>
              _DemoPayload.fromJson(payload! as Map<String, Object?>),
        );

        expect(run, isNotNull);
        expect(run!.value, isA<_DemoPayload>());
        expect(run.value!.foo, 'bar');
        expect(run.state.result, {'foo': 'bar'});
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'waitForCompletion does not decode when workflow is cancelled',
      () async {
        final flow = Flow(
          name: 'workflow.cancelled',
          build: (builder) {
            builder.step('noop', (ctx) async => 'done');
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          var decodeInvocations = 0;
          final runId = await workflowApp.startWorkflow('workflow.cancelled');
          await workflowApp.runtime.cancelWorkflow(runId);

          final run = await workflowApp.waitForCompletion<Object?>(
            runId,
            decode: (payload) {
              decodeInvocations += 1;
              return payload;
            },
          );

          expect(run, isNotNull);
          expect(run!.status, WorkflowStatus.cancelled);
          expect(run.value, isNull);
          expect(decodeInvocations, 0);
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('waitForCompletion returns non-terminal state on timeout', () async {
      final flow = Flow(
        name: 'workflow.timeout',
        build: (builder) {
          builder.step('sleep', (ctx) async {
            final resume = ctx.takeResumeData();
            if (resume != true) {
              ctx.sleep(const Duration(seconds: 5));
              return null;
            }
            return 'done';
          });
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.timeout');
        final result = await workflowApp.waitForCompletion(
          runId,
          timeout: const Duration(milliseconds: 100),
        );

        expect(result, isNotNull);
        expect(result!.timedOut, isTrue);
        expect(result.status, WorkflowStatus.suspended);
        expect(result.value, isNull);
      } finally {
        await workflowApp.shutdown();
      }
    });
  });
}

class _DemoPayload {
  const _DemoPayload(this.foo);

  factory _DemoPayload.fromJson(Map<String, Object?> json) =>
      _DemoPayload(json['foo'] as String);

  final String foo;
}
