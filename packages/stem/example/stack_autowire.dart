import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class PingTask implements TaskHandler<void> {
  @override
  String get name => 'demo.ping';

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
  final stack = StemStack.fromUrl(
    'redis://localhost:6379/0',
    adapters: const [StemRedisAdapter()],
    workflows: true,
    scheduling: true,
    uniqueTasks: true,
    requireRevokeStore: true,
  );

  final app = await StemApp.create(
    tasks: [PingTask()],
    broker: stack.broker,
    backend: stack.backend,
  );

  final workflowApp = await StemWorkflowApp.create(
    broker: stack.broker,
    backend: stack.backend,
    storeFactory: stack.workflowStore,
  );

  final scheduleFactory = stack.scheduleStore!;
  final scheduleStore = await scheduleFactory.create();
  final lockFactory = stack.lockStore!;
  final lockStore = await lockFactory.create();

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
