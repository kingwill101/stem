import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_rate_limit_delay_demo/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6381/0';
  final backendUrl =
      Platform.environment['STEM_RESULT_BACKEND_URL'] ?? 'redis://localhost:6381/1';
  final rateUrl =
      Platform.environment['STEM_RATE_LIMIT_URL'] ?? 'redis://localhost:6381/2';

  stdout.writeln('[worker] connecting to broker=$brokerUrl backend=$backendUrl');

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final rateLimiter = await connectRateLimiter(rateUrl);
  final registry = buildRegistry();
  final routing = buildRoutingRegistry();
  final subscriptions = attachSignalLogging();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    rateLimiter: rateLimiter,
    queue: 'throttled',
    consumerName:
        Platform.environment['WORKER_NAME'] ?? 'rate-limit-demo-worker',
    subscription: RoutingSubscription.singleQueue('throttled'),
    concurrency: 2,
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    await rateLimiter.close();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await worker.start();
}
