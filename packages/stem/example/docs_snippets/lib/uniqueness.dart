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

// #region uniqueness-enqueue
Future<String> enqueueDigest(TaskEnqueuer enqueuer) async {
  final firstId = await enqueuer.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
  );

  final secondId = await enqueuer.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
  );

  print('first enqueue id:  $firstId');
  print('second enqueue id: $secondId (dup is re-used)');
  return firstId;
}
// #endregion uniqueness-enqueue

// #region uniqueness-override-key
Future<String> enqueueWithOverride(TaskEnqueuer enqueuer) async {
  return enqueuer.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
    meta: const {UniqueTaskMetadata.override: 'digest-override-42'},
  );
}
// #endregion uniqueness-override-key

Future<void> main() async {
  // #region uniqueness-stem-worker
  final app = await StemApp.fromUrl(
    'memory://',
    tasks: [SendDigestTask()],
    uniqueTasks: true,
    uniqueTaskDefaultTtl: const Duration(minutes: 5),
    workerConfig: const StemWorkerConfig(
      queue: 'email',
      consumerName: 'unique-worker',
    ),
  );
  // #endregion uniqueness-stem-worker

  final digestTaskId = await enqueueDigest(app);
  await app.waitForTask<void>(
    digestTaskId,
    timeout: const Duration(seconds: 1),
  );
  final overrideTaskId = await enqueueWithOverride(app);
  await app.waitForTask<void>(
    overrideTaskId,
    timeout: const Duration(seconds: 1),
  );

  await app.close();
}
