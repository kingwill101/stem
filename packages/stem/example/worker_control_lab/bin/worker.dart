import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_worker_control_lab/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379/0';
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'] ??
      'redis://localhost:6379/1';
  final revokeUrl = Platform.environment['STEM_REVOKE_STORE_URL'] ??
      'redis://localhost:6379/2';
  final workerName =
      Platform.environment['WORKER_NAME'] ?? 'control-worker-${pid}';
  final concurrency =
      int.tryParse(Platform.environment['WORKER_CONCURRENCY'] ?? '') ?? 2;

  stdout.writeln(
    '[worker] starting name=$workerName broker=$brokerUrl backend=$backendUrl revoke=$revokeUrl',
  );

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final revokeStore = await connectRevokeStore(revokeUrl);
  final registry = buildRegistry();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    revokeStore: revokeStore,
    queue: controlQueue,
    subscription: RoutingSubscription.singleQueue(controlQueue),
    consumerName: workerName,
    concurrency: concurrency,
    prefetchMultiplier: 1,
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    await revokeStore.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await worker.start();
}
