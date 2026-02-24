import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class PingTask implements TaskHandler<void> {
  @override
  String get name => 'demo.ping';

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print('pong');
  }

  @override
  TaskEntrypoint? get isolateEntrypoint => null;
}

Future<void> main() async {
  const redisAdapters = [StemRedisAdapter()];
  final stack = StemStack.fromUrl(
    'redis://localhost:6379/0',
    adapters: redisAdapters,
    scheduling: true,
    uniqueTasks: true,
  );

  final scheduleFactory = stack.scheduleStore;
  if (scheduleFactory == null) {
    throw StateError('Scheduling enabled but schedule store factory missing.');
  }
  final lockFactory = stack.lockStore;
  if (lockFactory == null) {
    throw StateError('Unique tasks enabled but lock store factory missing.');
  }
  final scheduleStore = await scheduleFactory.create();
  final lockStore = await lockFactory.create();
  final app = await StemApp.fromUrl(
    'redis://localhost:6379/0',
    tasks: [PingTask()],
    adapters: redisAdapters,
    uniqueTasks: true,
    requireRevokeStore: true,
  );

  final workflowApp = await StemWorkflowApp.fromUrl(
    'redis://localhost:6379/0',
    adapters: redisAdapters,
  );

  final beat = Beat(
    store: scheduleStore,
    broker: app.broker,
    lockStore: lockStore,
  );

  try {
    await app.start();
    await workflowApp.start();
    await beat.start();

    await app.stem.enqueue('demo.ping');
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    await beat.stop();
    await workflowApp.shutdown();
    await app.shutdown();
    await scheduleFactory.dispose(scheduleStore);
    await lockFactory.dispose(lockStore);
  }
}
