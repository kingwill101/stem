import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

import 'package:stem_signals_demo/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://redis:6379/0';
  final workerName =
      Platform.environment['WORKER_NAME'] ?? 'signals-demo-worker';

  registerSignalLogging('worker');

  final broker = await RedisStreamsBroker.connect(brokerUrl);
  final registry = buildRegistry();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'default',
    consumerName: workerName,
    concurrency: 2,
    prefetchMultiplier: 1,
    retryStrategy: ExponentialJitterRetryStrategy(
      base: const Duration(seconds: 2),
      max: const Duration(seconds: 5),
    ),
  );

  await worker.start();

  void scheduleShutdown(ProcessSignal signal) {
    // ignore: avoid_print
    print('[signals][worker] received $signal, shutting down');
    worker.shutdown(mode: WorkerShutdownMode.soft).then((_) async {
      await broker.close();
      exit(0);
    });
  }

  ProcessSignal.sigint.watch().listen(scheduleShutdown);
  ProcessSignal.sigterm.watch().listen(scheduleShutdown);

  // Keep the worker running indefinitely.
  await Completer<void>().future;
}
