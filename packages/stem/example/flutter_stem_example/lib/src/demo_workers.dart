import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import 'demo_config.dart';
import 'demo_runtime.dart';
import 'demo_workflows.dart';

class DemoWorkerSpec {
  const DemoWorkerSpec({
    required this.id,
    required this.queues,
    required this.handlesWorkflows,
  });

  final String id;
  final List<String> queues;
  final bool handlesWorkflows;
}

const demoWorkerSpecs = [
  DemoWorkerSpec(
    id: primaryWorkerName,
    queues: [queueName],
    handlesWorkflows: true,
  ),
  DemoWorkerSpec(id: 'general-b', queues: [queueName], handlesWorkflows: true),
  DemoWorkerSpec(
    id: 'routing-worker',
    queues: [routingQueueName],
    handlesWorkflows: false,
  ),
];

/// Owns one independent standard core worker and its optional workflow layer.
class DemoWorkerRuntime {
  DemoWorkerRuntime(this.spec, this.app, {this.workflows});

  final DemoWorkerSpec spec;
  final StemApp app;
  final StemWorkflowApp? workflows;
  Future<void>? _closing;

  Future<void> start() async {
    await workflows?.startRuntime();
    await app.start();
  }

  Future<void> prepareBounded() async {
    final layer = workflows;
    if (layer != null) await prepareDemoWorkflowCallback(layer);
  }

  /// Idle is local to this worker's subscriptions, not to the worker group.
  Future<WorkerRunOutcome> runUntilIdle({
    required Duration budget,
    Duration shutdownReserve = const Duration(seconds: 5),
    Duration idleTimeout = const Duration(seconds: 1),
    Future<void>? cancellation,
  }) => app.worker.runUntilIdle(
    budget: budget,
    shutdownReserve: shutdownReserve,
    idleTimeout: idleTimeout,
    cancellation: cancellation,
  );

  Future<void> close() =>
      _closing ??= closeDemoRuntime(app, workflows: workflows);
}

Future<DemoWorkerRuntime> createDemoWorker(
  DemoWorkerSpec spec, {
  StemFlutterStorageLayout? layout,
}) async {
  final app = await createDemoApp(
    layout: layout,
    workerConfig: StemWorkerConfig(
      queue: spec.queues.first,
      subscription: RoutingSubscription(queues: spec.queues),
      consumerName: spec.id,
      concurrency: 1,
      prefetchMultiplier: 1,
      lifecycle: const WorkerLifecycleConfig(
        installSignalHandlers: false,
        maxTasksPerIsolate: 1,
      ),
    ),
  );
  try {
    final workflows = spec.handlesWorkflows
        ? await attachDemoWorkflows(app, layout: layout)
        : null;
    return DemoWorkerRuntime(spec, app, workflows: workflows);
  } catch (_) {
    await closeDemoRuntime(app);
    rethrow;
  }
}

Future<List<DemoWorkerRuntime>> createAdditionalDemoWorkers({
  StemFlutterStorageLayout? layout,
}) async {
  final workers = <DemoWorkerRuntime>[];
  try {
    for (final spec in demoWorkerSpecs.skip(1)) {
      workers.add(await createDemoWorker(spec, layout: layout));
    }
    return workers;
  } catch (_) {
    await Future.wait(workers.map((worker) => worker.close()));
    rethrow;
  }
}
