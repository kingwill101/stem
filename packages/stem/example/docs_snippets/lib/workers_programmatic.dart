// Programmatic worker and producer examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region workers-producer-minimal
Future<void> minimalProducer() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<void>(
        name: 'email.send',
        entrypoint: (context, args) async {
          final to = args['to'] as String? ?? 'friend';
          print('Queued email to $to');
          return null;
        },
      ),
    ],
  );

  final taskId = await app.enqueue(
    'email.send',
    args: {'to': 'hello@example.com', 'subject': 'Welcome'},
  );

  print('Enqueued $taskId');
  await app.waitForTask<void>(taskId);
  await app.close();
}
// #endregion workers-producer-minimal

// #region workers-producer-redis
Future<void> redisProducer() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final client = await StemClient.fromUrl(
    brokerUrl,
    adapters: const [StemRedisAdapter()],
    overrides: StemStoreOverrides(backend: '$brokerUrl/1'),
    tasks: [
      FunctionTaskHandler<void>(
        name: 'report.generate',
        entrypoint: (context, args) async {
          final id = args['reportId'] as String? ?? 'unknown';
          print('Queued report $id');
          return null;
        },
      ),
    ],
  );

  await client.enqueue(
    'report.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports'),
  );
  await client.close();
}
// #endregion workers-producer-redis

// #region workers-producer-signed
Future<void> signedProducer() async {
  final config = StemConfig.fromEnvironment();
  final signer = PayloadSigner.maybe(config.signing);
  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => RedisStreamsBroker.connect(
        config.brokerUrl,
        tls: config.tls,
      ),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory.inMemory(),
    tasks: [
      FunctionTaskHandler<void>(
        name: 'billing.charge',
        entrypoint: (context, args) async {
          final customerId = args['customerId'] as String? ?? 'unknown';
          print('Queued charge for $customerId');
          return null;
        },
      ),
    ],
    signer: signer,
  );

  await client.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
  );
  await client.close();
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
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    backend: backend,
    tasks: [EmailTask()],
    queue: 'default',
  );

  await worker.start();
}
// #endregion workers-worker-minimal

// #region workers-worker-redis
Future<void> redisWorker() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';

  final worker = Worker(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
    tasks: [RedisEmailTask()],
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

  final worker = Worker(
    broker: InMemoryBroker(),
    backend: InMemoryResultBackend(),
    tasks: [FlakyTask()],
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
  StemRuntime({required this.tasks, required this.brokerUrl});

  final List<TaskHandler<Object?>> tasks;
  final String brokerUrl;

  final InMemoryBroker _stemBroker = InMemoryBroker();
  final InMemoryResultBackend _stemBackend = InMemoryResultBackend();
  final InMemoryBroker _workerBroker = InMemoryBroker();
  final InMemoryResultBackend _workerBackend = InMemoryResultBackend();

  late final Stem stem = Stem(
    broker: _stemBroker,
    backend: _stemBackend,
    tasks: tasks,
  );

  late final Worker worker = Worker(
    broker: _workerBroker,
    backend: _workerBackend,
    tasks: tasks,
  );

  Future<void> start() async {
    await worker.start();
  }

  Future<void> stop() async {
    await worker.shutdown();
    await _workerBackend.close();
    await _workerBroker.close();
    await _stemBackend.close();
    await _stemBroker.close();
  }
}
// #endregion workers-bootstrap

Future<void> main() async {
  await minimalProducer();
}
