import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_dlq_sandbox/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6382/0';
  final backendUrl =
      Platform.environment['STEM_RESULT_BACKEND_URL'] ?? 'redis://localhost:6382/1';

  stdout.writeln('[worker] connecting broker=$brokerUrl backend=$backendUrl');

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();
  final subscriptions = attachSignalLogging();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: queueName(),
    consumerName:
        Platform.environment['WORKER_NAME'] ?? 'dlq-sandbox-worker',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await worker.start();
}
