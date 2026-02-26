// Demonstrates workflow runtime metadata, channel markers, manifest output,
// and run/step drilldown views.
// Run with: dart run example/workflows/runtime_metadata_views.dart

import 'dart:convert';

import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry();
  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final store = InMemoryWorkflowStore();
  final runtime = WorkflowRuntime(
    stem: stem,
    store: store,
    eventBus: InMemoryEventBus(store),
    queue: 'workflow',
    continuationQueue: 'workflow-continue',
    executionQueue: 'workflow-step',
  );

  registry
    ..register(runtime.workflowRunnerHandler())
    ..register(
      FunctionTaskHandler<void>.inline(
        name: 'example.noop',
        entrypoint: (context, args) async => null,
      ),
    );

  runtime.registerWorkflow(
    Flow(
      name: 'example.runtime.features',
      build: (flow) {
        flow.step('dispatch-task', (ctx) async {
          await ctx.enqueuer!.enqueue(
            'example.noop',
            args: const {'payload': true},
            meta: const {'origin': 'runtime_metadata_views'},
          );
          return 'done';
        });
      },
    ).definition,
  );

  try {
    final runId = await runtime.startWorkflow(
      'example.runtime.features',
      params: const {'tenant': 'acme', 'requestId': 'req-42'},
    );

    final orchestrationDelivery = await broker
        .consume(RoutingSubscription.singleQueue('workflow'))
        .first
        .timeout(const Duration(seconds: 1));

    print('--- Orchestration task metadata ---');
    print(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(orchestrationDelivery.envelope.meta),
    );

    await runtime.executeRun(runId);

    final executionDelivery = await broker
        .consume(RoutingSubscription.singleQueue('workflow-step'))
        .first
        .timeout(const Duration(seconds: 1));

    print('\n--- Execution task metadata ---');
    print(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(executionDelivery.envelope.meta),
    );

    final runView = await runtime.viewRun(runId);
    final runDetail = await runtime.viewRunDetail(runId);

    print('\n--- Workflow manifest ---');
    print(
      const JsonEncoder.withIndent('  ').convert(
        runtime
            .workflowManifest()
            .map((entry) => entry.toJson())
            .toList(growable: false),
      ),
    );

    print('\n--- Run view ---');
    print(const JsonEncoder.withIndent('  ').convert(runView?.toJson()));

    print('\n--- Run detail view ---');
    print(const JsonEncoder.withIndent('  ').convert(runDetail?.toJson()));
  } finally {
    await runtime.dispose();
    await backend.close();
    broker.dispose();
  }
}
