import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import '../lib/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://redis:6379/0';
  final workerName = Platform.environment['WORKER_NAME'] ?? 'retry-demo-worker';

  final broker = await RedisStreamsBroker.connect(
    brokerUrl,
    blockTime: const Duration(milliseconds: 100),
    claimInterval: const Duration(milliseconds: 200),
    defaultVisibilityTimeout: const Duration(seconds: 2),
  );
  final registry = buildRegistry();
  final backend = InMemoryResultBackend();

  // #region reliability-retry-worker
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'retry-demo',
    consumerName: workerName,
    retryStrategy: ExponentialJitterRetryStrategy(
      base: const Duration(milliseconds: 200),
      max: const Duration(seconds: 1),
    ),
  );
  // #endregion reliability-retry-worker

  // #region reliability-retry-runtime-signals
  final subscriptions = attachLogging('worker');
  final shutdownCompleted = Completer<void>();
  var shuttingDown = false;

  final shutdownSubscription = StemSignals.workerShutdown.connect((payload, _) {
    if (!shutdownCompleted.isCompleted) {
      shutdownCompleted.complete();
    }
  });
  subscriptions.add(shutdownSubscription);

  final failureSubscription = StemSignals.onTaskFailure((payload, _) async {
    if (shuttingDown) return;
    shuttingDown = true;
    // Give the logs a moment to flush before shutting down.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await worker.shutdown(mode: WorkerShutdownMode.hard);
  });
  subscriptions.add(failureSubscription);
  // #endregion reliability-retry-runtime-signals

  await worker.start();
  await shutdownCompleted.future;

  for (final sub in subscriptions) {
    sub.cancel();
  }

  await backend.dispose();
  await broker.close();
}
