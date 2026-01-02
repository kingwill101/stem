// Rate limiting examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region rate-limit-demo-limiter
class DemoRateLimiter implements RateLimiter {
  // #region rate-limit-demo-limiter-config
  DemoRateLimiter({required this.capacity, required this.interval});

  final int capacity;
  final Duration interval;
  int _used = 0;
  DateTime _windowStart = DateTime.now();
  // #endregion rate-limit-demo-limiter-config

  // #region rate-limit-demo-limiter-acquire
  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    final window = interval ?? this.interval;
    final now = DateTime.now();
    final elapsed = now.difference(_windowStart);
    if (elapsed >= window) {
      _windowStart = now;
      _used = 0;
    }

    if (_used + tokens <= capacity) {
      _used += tokens;
      return RateLimitDecision(allowed: true, meta: {'key': key});
    }

    final retryAfter = window - elapsed;
    return RateLimitDecision(
      allowed: false,
      retryAfter: retryAfter.isNegative ? Duration.zero : retryAfter,
      meta: {'key': key},
    );
  }

  // #endregion rate-limit-demo-limiter-acquire
}
// #endregion rate-limit-demo-limiter

// #region rate-limit-task
// #region rate-limit-task-options
class RateLimitedTask extends TaskHandler<void> {
  @override
  String get name => 'demo.rateLimited';

  @override
  TaskOptions get options => const TaskOptions(
    rateLimit: '10/s',
    maxRetries: 3,
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final actor = args['actor'] as String? ?? 'anonymous';
    print('Handled rate-limited task for $actor');
  }
}
// #endregion rate-limit-task-options
// #endregion rate-limit-task

// #region rate-limit-producer
Future<String> enqueueRateLimited(Stem stem) async {
  return stem.enqueue(
    'demo.rateLimited',
    args: {'actor': 'acme'},
    headers: const {'tenant': 'acme'},
  );
}
// #endregion rate-limit-producer

Future<void> main() async {
  // #region rate-limit-demo-registry
  // #region rate-limit-worker
  final limiter = DemoRateLimiter(
    capacity: 2,
    interval: const Duration(seconds: 1),
  );
  final workerConfig = StemWorkerConfig(rateLimiter: limiter);
  // #endregion rate-limit-worker
  final app = await StemApp.inMemory(
    tasks: [RateLimitedTask()],
    workerConfig: workerConfig,
  );
  // #endregion rate-limit-demo-registry

  // #region rate-limit-demo-worker-start
  await app.start();
  // #endregion rate-limit-demo-worker-start

  // #region rate-limit-demo-stem
  final stem = app.stem;
  // #endregion rate-limit-demo-stem
  // #region rate-limit-demo-enqueue
  await enqueueRateLimited(stem);
  // #endregion rate-limit-demo-enqueue
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // #region rate-limit-demo-shutdown
  await app.shutdown();
  // #endregion rate-limit-demo-shutdown
}
