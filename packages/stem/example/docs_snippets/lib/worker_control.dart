// Worker control examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';

// #region worker-control-autoscale
final worker = Worker(
  broker: InMemoryBroker(),
  registry: SimpleTaskRegistry(),
  backend: InMemoryResultBackend(),
  queue: 'critical',
  concurrency: 12,
  autoscale: const WorkerAutoscaleConfig(
    enabled: true,
    minConcurrency: 2,
    maxConcurrency: 12,
    scaleUpStep: 2,
    scaleDownStep: 1,
    idlePeriod: Duration(seconds: 45),
    tick: Duration(milliseconds: 250),
  ),
);
// #endregion worker-control-autoscale

// #region worker-control-inline
class InlineReportTask extends TaskHandler<void> {
  @override
  String get name => 'tasks.inline-report';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    for (final chunk in args['chunks'] as List<String>) {
      await processChunk(chunk);
      context.heartbeat();
    }
  }
}
// #endregion worker-control-inline

// #region worker-control-isolate
class ImageRenderTask extends TaskHandler<void> {
  @override
  String get name => 'tasks.render-image';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  TaskEntrypoint? get isolateEntrypoint => renderImageEntrypoint;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

Future<void> renderImageEntrypoint(
  TaskInvocationContext ctx,
  Map<String, Object?> args,
) async {
  final tiles = args['tiles'] as List<ImageTile>;
  for (var i = 0; i < tiles.length; i++) {
    await renderTile(tiles[i]);

    if (i % 5 == 0) {
      ctx.heartbeat();
      ctx.progress(i / tiles.length);
    }
  }
}
// #endregion worker-control-isolate

// #region worker-control-crunch
Future<void> crunch(TaskInvocationContext ctx, Map<String, Object?> args) async {
  final items = args['items'] as List<Object?>;
  for (var i = 0; i < items.length; i++) {
    await process(items[i]);

    if (i % 10 == 0) {
      ctx.heartbeat();
      ctx.progress(i / items.length);
    }
  }
}
// #endregion worker-control-crunch

// #region worker-control-lifecycle
final lifecycleWorker = Worker(
  broker: InMemoryBroker(),
  registry: SimpleTaskRegistry(),
  backend: InMemoryResultBackend(),
  lifecycle: const WorkerLifecycleConfig(
    maxTasksPerIsolate: 500,
    maxMemoryPerIsolateBytes: 512 * 1024 * 1024,
  ),
);
// #endregion worker-control-lifecycle

Future<void> processChunk(String chunk) async {}

Future<void> renderTile(ImageTile tile) async {}

Future<void> process(Object? item) async {}

class ImageTile {}

Future<void> main() async {
  await worker.start();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await worker.shutdown();
}
