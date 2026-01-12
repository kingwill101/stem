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

// #region retry-backoff-custom-worker
const fixedDelayWorkerConfig = StemWorkerConfig(
  retryStrategy: FixedDelayRetryStrategy(Duration(seconds: 1)),
);
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
  // #region retry-backoff-worker
  final workerConfig = StemWorkerConfig(retryStrategy: retryStrategy);
  // #endregion retry-backoff-worker
  final app = await StemApp.inMemory(
    tasks: [FlakyTask()],
    workerConfig: workerConfig,
  );
  await app.start();

  final taskId = await app.stem.enqueue('demo.flaky');
  await app.stem.waitForTask<void>(taskId, timeout: const Duration(seconds: 5));

  await app.close();
}
