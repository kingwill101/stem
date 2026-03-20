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

final invocationParentDefinition = TaskDefinition.noArgs<void>(
  name: 'tasks.invocation_parent',
);

class ParentTask extends TaskHandler<void> {
  static final definition = TaskDefinition.noArgs<void>(
    name: 'tasks.parent',
    metadata: TaskMetadata(
      description: 'Parent task that enqueues follow-up work.',
    ),
  );

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  TaskMetadata get metadata => definition.metadata;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    await childDefinition.enqueue(
      context,
      const ChildArgs('from-parent'),
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
  await childDefinition
      .prepareEnqueue(const ChildArgs('from-invocation-builder'))
      .priority(5)
      .delay(const Duration(milliseconds: 100))
      .enqueue(context);
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
      name: invocationParentDefinition.name,
      entrypoint: invocationParentEntrypoint,
      options: const TaskOptions(queue: 'default'),
      metadata: invocationParentDefinition.metadata,
    ),
  ];

  final app = await StemApp.inMemory(
    tasks: tasks,
    workerConfig: const StemWorkerConfig(consumerName: 'example-worker'),
  );

  await ParentTask.definition.enqueue(app);
  await invocationParentDefinition.enqueue(app);
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
