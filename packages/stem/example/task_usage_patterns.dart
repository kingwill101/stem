import 'dart:async';

import 'package:stem/stem.dart';

class ChildArgs {
  const ChildArgs(this.value);

  final String value;
}

final childDefinition = TaskDefinition<ChildArgs, String>(
  name: 'tasks.child',
  encodeArgs: (args) => {'value': args.value},
  metadata: const TaskMetadata(description: 'Typed child task example'),
);

class ParentTask extends TaskHandler<void> {
  @override
  String get name => 'tasks.parent';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  TaskMetadata get metadata => const TaskMetadata(
    description: 'Parent task that enqueues follow-up work.',
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    await context.enqueue(
      'tasks.child',
      args: {'value': 'from-parent'},
      enqueueOptions: TaskEnqueueOptions(
        countdown: const Duration(milliseconds: 200),
        queue: 'default',
      ),
    );

    await childDefinition.enqueue(context, const ChildArgs('typed'));
  }
}

FutureOr<Object?> childEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  final value = args['value'] as String? ?? 'unknown';
  // Example output keeps the script runnable without adding logging setup.
  // ignore: avoid_print
  print('[child] value=$value attempt=${context.attempt}');
  return 'ok';
}

FutureOr<Object?> invocationParentEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await context
      .enqueueBuilder(
        definition: childDefinition,
        args: const ChildArgs('from-invocation-builder'),
      )
      .priority(5)
      .delay(const Duration(milliseconds: 100))
      .enqueue();
  return null;
}

Future<void> main() async {
  final tasks = <TaskHandler<Object?>>[
    ParentTask(),
    FunctionTaskHandler<String>.inline(
      name: childDefinition.name,
      entrypoint: childEntrypoint,
      options: const TaskOptions(queue: 'default'),
      metadata: childDefinition.metadata,
    ),
    FunctionTaskHandler<void>.inline(
      name: 'tasks.invocation_parent',
      entrypoint: invocationParentEntrypoint,
      options: const TaskOptions(queue: 'default'),
    ),
  ];

  final app = await StemApp.inMemory(
    tasks: tasks,
    workerConfig: const StemWorkerConfig(consumerName: 'example-worker'),
  );

  await app.enqueue('tasks.parent', args: const {});
  await app.enqueue('tasks.invocation_parent', args: const {});
  final directTaskId = await childDefinition.enqueue(
    app,
    const ChildArgs('direct-call'),
  );
  final directResult = await childDefinition.waitFor(
    app,
    directTaskId,
    timeout: const Duration(seconds: 1),
  );
  // Example output keeps the script runnable without adding logging setup.
  // ignore: avoid_print
  print('[direct] result=${directResult?.value}');

  final inlineResult = await childDefinition.enqueueAndWait(
    app,
    const ChildArgs('inline-wait'),
    timeout: const Duration(seconds: 1),
  );
  // Example output keeps the script runnable without adding logging setup.
  // ignore: avoid_print
  print('[inline] result=${inlineResult?.value}');

  await app.close();
}
