import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_ops_health_suite/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);

  final registry = buildRegistry();
  final observability = ObservabilityConfig.fromEnvironment();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: opsQueue,
    subscription: RoutingSubscription.singleQueue(opsQueue),
    consumerName: 'ops-worker',
    concurrency: 2,
    heartbeatInterval: const Duration(seconds: 5),
    workerHeartbeatInterval: const Duration(seconds: 5),
    observability: observability,
  );

  await worker.start();
  stdout.writeln('[worker] running health demo on "$opsQueue"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}
