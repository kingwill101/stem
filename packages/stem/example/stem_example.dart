import 'dart:async';
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
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final backend = await RedisResultBackend.connect('redis://localhost:6379/1');

  final stem = Stem(broker: broker, backend: backend, tasks: [HelloTask()]);
  final worker = Worker(
    broker: broker,
    backend: backend,
    tasks: [HelloTask()],
  );
  // #endregion getting-started-runtime-setup

  // #region getting-started-enqueue
  unawaited(worker.start());
  // Map-based enqueue for quick scripts or one-off calls.
  await stem.enqueue('demo.hello', args: {'name': 'Stem'});

  // Typed helper with TaskDefinition for compile-time safety.
  await HelloTask.definition(const HelloArgs(name: 'Stem')).enqueue(stem);
  await Future<void>.delayed(const Duration(seconds: 1));
  await worker.shutdown();
  await broker.close();
  await backend.close();
  // #endregion getting-started-enqueue
}
