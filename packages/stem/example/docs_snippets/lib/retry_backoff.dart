// Retry backoff examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

class FlakyTask extends TaskHandler<void> {
  @override
  String get name => 'demo.flaky';

  // #region retry-backoff-task-options
  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);
  // #endregion retry-backoff-task-options

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

// #region retry-backoff-custom-strategy
class FixedDelayRetryStrategy implements RetryStrategy {
  const FixedDelayRetryStrategy(this.delay);

  final Duration delay;

  @override
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace) => delay;
}
// #endregion retry-backoff-custom-strategy

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

// #region retry-backoff-custom-worker
Worker buildFixedDelayWorker({
  required Broker broker,
  required ResultBackend backend,
  required TaskRegistry registry,
}) {
  return Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    retryStrategy: const FixedDelayRetryStrategy(Duration(seconds: 1)),
  );
}
// #endregion retry-backoff-custom-worker

// #region retry-backoff-signals
void registerRetrySignals() {
  StemSignals.taskRetry.connect((payload, _) {
    print('Retry scheduled at ${payload.nextRetryAt}');
  });
}
// #endregion retry-backoff-signals

Future<void> main() async {
  registerRetrySignals();
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
  await backend.dispose();
}
