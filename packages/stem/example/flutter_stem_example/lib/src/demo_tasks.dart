import 'package:stem/stem.dart';

import 'demo_config.dart';

Future<Object?> _sleepEchoTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = args['label'] as String? ?? 'job';
  final delayMs = args['delayMs'] as int? ?? 1500;

  await Future<void>.delayed(Duration(milliseconds: delayMs));

  return 'Completed $label at ${DateTime.now().toIso8601String()}';
}

List<TaskHandler<Object?>> createTaskHandlers() {
  return <TaskHandler<Object?>>[
    FunctionTaskHandler<String>.inline(
      name: taskName,
      entrypoint: _sleepEchoTask,
      options: const TaskOptions(queue: queueName),
      metadata: const TaskMetadata(
        description: 'SQLite-backed mobile demo task.',
        tags: <String>['flutter', 'sqlite', 'mobile'],
      ),
    ),
  ];
}
