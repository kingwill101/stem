// Uniqueness examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class SendDigestTask extends TaskHandler<void> {
  @override
  String get name => 'email.sendDigest';

  // #region uniqueness-task-options
  @override
  TaskOptions get options => const TaskOptions(
    queue: 'email',
    unique: true,
    uniqueFor: Duration(minutes: 15),
    maxRetries: 2,
  );
  // #endregion uniqueness-task-options

  @override
  TaskMetadata get metadata => const TaskMetadata(
    description: 'Send a user digest email once per interval',
    idempotent: true,
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final userId = args['userId'];
    print(
      '[worker] sending digest for user $userId (attempt ${context.attempt})',
    );
  }
}

// #region uniqueness-coordinator-inmemory
UniqueTaskCoordinator buildInMemoryCoordinator() {
  final lockStore = InMemoryLockStore();
  return UniqueTaskCoordinator(
    lockStore: lockStore,
    defaultTtl: const Duration(minutes: 5),
  );
}
// #endregion uniqueness-coordinator-inmemory

// #region uniqueness-coordinator-redis
Future<UniqueTaskCoordinator> buildRedisCoordinator() async {
  final redisUrl =
      Platform.environment['STEM_LOCK_STORE_URL'] ?? 'redis://localhost:6379/5';
  final lockStore = await RedisLockStore.connect(redisUrl);
  return UniqueTaskCoordinator(
    lockStore: lockStore,
    defaultTtl: const Duration(minutes: 5),
  );
}
// #endregion uniqueness-coordinator-redis

class UniqueRuntime {
  const UniqueRuntime({
    required this.broker,
    required this.backend,
    required this.registry,
    required this.stem,
    required this.worker,
  });

  final InMemoryBroker broker;
  final InMemoryResultBackend backend;
  final TaskRegistry registry;
  final Stem stem;
  final Worker worker;
}

// #region uniqueness-stem-worker
UniqueRuntime buildUniqueRuntime(UniqueTaskCoordinator coordinator) {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()..register(SendDigestTask());

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    uniqueTaskCoordinator: coordinator,
  );
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    uniqueTaskCoordinator: coordinator,
    queue: 'email',
    consumerName: 'unique-worker',
  );

  return UniqueRuntime(
    broker: broker,
    backend: backend,
    registry: registry,
    stem: stem,
    worker: worker,
  );
}
// #endregion uniqueness-stem-worker

// #region uniqueness-enqueue
Future<void> enqueueDigest(Stem stem) async {
  final firstId = await stem.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
    options: const TaskOptions(
      queue: 'email',
      unique: true,
      uniqueFor: Duration(minutes: 15),
    ),
  );

  final secondId = await stem.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
    options: const TaskOptions(
      queue: 'email',
      unique: true,
      uniqueFor: Duration(minutes: 15),
    ),
  );

  print('first enqueue id:  $firstId');
  print('second enqueue id: $secondId (dup is re-used)');
}
// #endregion uniqueness-enqueue

// #region uniqueness-override-key
Future<void> enqueueWithOverride(Stem stem) async {
  await stem.enqueue(
    'orders.sync',
    args: const {'id': 42},
    options: const TaskOptions(unique: true, uniqueFor: Duration(minutes: 10)),
    meta: const {UniqueTaskMetadata.override: 'order-42'},
  );
}
// #endregion uniqueness-override-key

Future<void> main() async {
  final coordinator = buildInMemoryCoordinator();
  final runtime = buildUniqueRuntime(coordinator);

  unawaited(runtime.worker.start());

  await enqueueDigest(runtime.stem);
  await enqueueWithOverride(runtime.stem);

  await Future<void>.delayed(const Duration(milliseconds: 500));

  await runtime.worker.shutdown();
  runtime.broker.dispose();
  await runtime.backend.dispose();
}
