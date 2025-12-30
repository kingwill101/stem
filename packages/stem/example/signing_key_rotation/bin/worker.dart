import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_signing_key_rotation/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);
  final signer = PayloadSigner.maybe(config.signing);

  final registry = buildRegistry();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: rotationQueue,
    subscription: RoutingSubscription.singleQueue(rotationQueue),
    consumerName: 'rotation-worker',
    concurrency: 2,
    signer: signer,
    prefetchMultiplier: 1,
  );

  await worker.start();
  stdout.writeln('[worker] verifying signatures on "$rotationQueue"');

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
