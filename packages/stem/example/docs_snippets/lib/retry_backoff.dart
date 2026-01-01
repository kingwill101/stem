// Retry backoff examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

class FlakyTask extends TaskHandler<void> {
  @override
  String get name => 'demo.flaky';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (context.attempt < 1) {
      throw StateError('Simulated failure');
    }
    print('Succeeded on attempt ${context.attempt}');
  }
}

// #region retry-backoff-strategy
final RetryStrategy retryStrategy = ExponentialJitterRetryStrategy(
  base: const Duration(milliseconds: 200),
  max: const Duration(seconds: 2),
);
// #endregion retry-backoff-strategy

// #region retry-backoff-worker
Worker buildRetryWorker({
  required Broker broker,
  required ResultBackend backend,
  required TaskRegistry registry,
}) {
  return Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    retryStrategy: retryStrategy,
  );
}
// #endregion retry-backoff-worker

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()..register(FlakyTask());

  final worker = buildRetryWorker(
    broker: broker,
    backend: backend,
    registry: registry,
  );
  await worker.start();

  final stem = Stem(broker: broker, backend: backend, registry: registry);
  final taskId = await stem.enqueue('demo.flaky');
  await stem.waitForTask<void>(taskId, timeout: const Duration(seconds: 5));

  await worker.shutdown();
  broker.dispose();
}
