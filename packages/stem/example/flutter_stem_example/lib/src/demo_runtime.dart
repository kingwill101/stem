import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import 'demo_config.dart';
import 'demo_tasks.dart';

/// A normal core app with explicit queue subscription and worker identity.
Future<StemApp> createDemoApp({
  StemFlutterStorageLayout? layout,
  StemWorkerConfig? workerConfig,
}) => StemFlutterSqlite.createApp(
  module: demoModule,
  layout: layout,
  workerConfig:
      workerConfig ??
      StemWorkerConfig(
        queue: queueName,
        consumerName: primaryWorkerName,
        subscription: RoutingSubscription.singleQueue(queueName),
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
          maxTasksPerIsolate: 1,
        ),
      ),
);

/// The workflow layer borrows its task app. Join polling and worker execution
/// before closing either store; no worker owns another worker's connections.
Future<void> closeDemoRuntime(StemApp app, {StemWorkflowApp? workflows}) async {
  try {
    await workflows?.runtime.dispose();
  } finally {
    try {
      await app.worker.shutdown();
    } finally {
      try {
        await workflows?.close();
      } finally {
        await app.close();
      }
    }
  }
}
