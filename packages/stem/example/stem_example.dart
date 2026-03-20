import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class HelloTask implements TaskHandler<void> {
  // #region getting-started-task-definition
  static final definition = TaskDefinition<HelloArgs, void>(
    name: 'demo.hello',
    encodeArgs: (args) => {'name': args.name},
    metadata: TaskMetadata(description: 'Simple hello world example'),
  );

  @override
  String get name => 'demo.hello';

  @override
  TaskMetadata get metadata => definition.metadata;
  // #endregion getting-started-task-definition

  // #region getting-started-task-options
  @override
  TaskOptions get options => const TaskOptions(
    queue: 'default',
    maxRetries: 3,
    rateLimit: '10/s',
    visibilityTimeout: Duration(seconds: 60),
  );
  // #endregion getting-started-task-options

  // #region getting-started-task-handler
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final who = args['name'] as String? ?? 'world';
    print('Hello $who (attempt ${context.attempt})');
  }
  // #endregion getting-started-task-handler

  @override
  TaskEntrypoint? get isolateEntrypoint => null;
}

class HelloArgs {
  const HelloArgs({required this.name});

  final String name;
}

Future<void> main() async {
  // #region getting-started-runtime-setup
  final app = await StemApp.fromUrl(
    'redis://localhost:6379',
    tasks: [HelloTask()],
    adapters: const [StemRedisAdapter()],
    overrides: const StemStoreOverrides(backend: 'redis://localhost:6379/1'),
  );
  // #endregion getting-started-runtime-setup

  // #region getting-started-enqueue
  // Map-based enqueue for quick scripts or one-off calls.
  final taskId = await app.enqueue('demo.hello', args: {'name': 'Stem'});
  await app.waitForTask<void>(taskId, timeout: const Duration(seconds: 2));

  // Typed helper with TaskDefinition for compile-time safety.
  final typedTaskId = await HelloTask.definition.enqueue(
    app,
    const HelloArgs(name: 'Stem'),
  );
  await HelloTask.definition.waitFor(
    app,
    typedTaskId,
    timeout: const Duration(seconds: 2),
  );
  await app.close();
  // #endregion getting-started-enqueue
}
