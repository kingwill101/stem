// Programmatic worker and producer examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region workers-producer-minimal
Future<void> minimalProducer() async {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'email.send',
        entrypoint: (context, args) async {
          final to = args['to'] as String? ?? 'friend';
          print('Queued email to $to');
          return null;
        },
      ),
    );

  final stem = Stem(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  final taskId = await stem.enqueue(
    'email.send',
    args: {'to': 'hello@example.com', 'subject': 'Welcome'},
  );

  print('Enqueued $taskId');
}
// #endregion workers-producer-minimal

// #region workers-producer-redis
Future<void> redisProducer() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final broker = await RedisStreamsBroker.connect(brokerUrl);
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'report.generate',
        entrypoint: (context, args) async {
          final id = args['reportId'] as String? ?? 'unknown';
          print('Queued report $id');
          return null;
        },
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
  );

  await stem.enqueue(
    'report.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports'),
  );
}
// #endregion workers-producer-redis

// #region workers-producer-signed
Future<void> signedProducer() async {
  final config = StemConfig.fromEnvironment();
  final signer = PayloadSigner.maybe(config.signing);
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'billing.charge',
        entrypoint: (context, args) async {
          final customerId = args['customerId'] as String? ?? 'unknown';
          print('Queued charge for $customerId');
          return null;
        },
      ),
    );

  final stem = Stem(
    broker: await RedisStreamsBroker.connect(config.brokerUrl, tls: config.tls),
    registry: registry,
    backend: InMemoryResultBackend(),
    signer: signer,
  );

  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
  );
}
// #endregion workers-producer-signed

// #region workers-worker-minimal
class EmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String;
    print('Sending to $to (attempt ${context.attempt})');
  }
}

Future<void> minimalWorker() async {
  final registry = SimpleTaskRegistry()..register(EmailTask());
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'default',
  );

  await worker.start();
}
// #endregion workers-worker-minimal

// #region workers-worker-redis
Future<void> redisWorker() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final registry = SimpleTaskRegistry()..register(RedisEmailTask());

  final worker = Worker(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    registry: registry,
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
    queue: 'default',
    concurrency: Platform.numberOfProcessors,
  );

  await worker.start();
}

class RedisEmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'default',
        maxRetries: 3,
        visibilityTimeout: Duration(seconds: 30),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
// #endregion workers-worker-redis

// #region workers-worker-retry
class FlakyTask extends TaskHandler<void> {
  @override
  String get name => 'demo.flaky';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (context.attempt < 2) {
      throw StateError('Simulated failure');
    }
    print('Succeeded on attempt ${context.attempt}');
  }
}

Future<void> retryWorker() async {
  StemSignals.taskRetry.connect((payload, _) {
    print('[retry] next run at: ${payload.nextRetryAt}');
  });

  final registry = SimpleTaskRegistry()..register(FlakyTask());
  final worker = Worker(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
    retryStrategy: ExponentialJitterRetryStrategy(
      base: const Duration(milliseconds: 200),
      max: const Duration(seconds: 1),
    ),
  );

  await worker.start();
}
// #endregion workers-worker-retry

// #region workers-bootstrap
class StemRuntime {
  StemRuntime({required this.registry, required this.brokerUrl});

  final TaskRegistry registry;
  final String brokerUrl;

  late final Stem stem = Stem(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  late final Worker worker = Worker(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  Future<void> start() async {
    await worker.start();
  }

  Future<void> stop() async {
    await worker.shutdown();
  }
}
// #endregion workers-bootstrap

Future<void> main() async {
  await minimalProducer();
}
