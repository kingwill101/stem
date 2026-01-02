import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_progress_heartbeat/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379/0';
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'] ??
      'redis://localhost:6379/1';
  final workerName =
      Platform.environment['WORKER_NAME'] ?? 'progress-worker-${pid}';

  stdout.writeln('[worker] broker=$brokerUrl backend=$backendUrl');

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();

  // #region reliability-heartbeat-worker
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: progressQueue,
    subscription: RoutingSubscription.singleQueue(progressQueue),
    consumerName: workerName,
    heartbeatInterval: const Duration(seconds: 2),
    workerHeartbeatInterval: const Duration(seconds: 5),
    prefetchMultiplier: 1,
  );
  // #endregion reliability-heartbeat-worker

  attachWorkerEventLogging(worker);

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await worker.start();
}
