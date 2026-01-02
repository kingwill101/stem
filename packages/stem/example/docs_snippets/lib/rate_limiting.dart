// Rate limiting examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region rate-limit-demo-limiter
class DemoRateLimiter implements RateLimiter {
  DemoRateLimiter({required this.capacity, required this.interval});

  final int capacity;
  final Duration interval;
  int _used = 0;
  DateTime _windowStart = DateTime.now();

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
}
// #endregion rate-limit-demo-limiter

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

// #region rate-limit-worker
Worker buildRateLimitedWorker({
  required Broker broker,
  required ResultBackend backend,
  required TaskRegistry registry,
}) {
  final limiter = DemoRateLimiter(
    capacity: 2,
    interval: const Duration(seconds: 1),
  );
  return Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    rateLimiter: limiter,
  );
}
// #endregion rate-limit-worker

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
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()..register(RateLimitedTask());

  final worker = buildRateLimitedWorker(
    broker: broker,
    backend: backend,
    registry: registry,
  );
  await worker.start();

  final stem = Stem(broker: broker, backend: backend, registry: registry);
  await enqueueRateLimited(stem);
  await Future<void>.delayed(const Duration(milliseconds: 200));

  await worker.shutdown();
  broker.dispose();
}
