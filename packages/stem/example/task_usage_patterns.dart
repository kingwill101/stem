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

    await childDefinition.enqueueWith(context, const ChildArgs('typed'));
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
  final call = context
      .enqueueBuilder(
        definition: childDefinition,
        args: const ChildArgs('from-invocation-builder'),
      )
      .priority(5)
      .delay(const Duration(milliseconds: 100))
      .build();

  await context.enqueueCall(call);
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

  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final worker = Worker(
    broker: broker,
    backend: backend,
    tasks: tasks,
    consumerName: 'example-worker',
  );
  final stem = Stem(broker: broker, backend: backend, tasks: tasks);

  unawaited(worker.start());

  await stem.enqueue('tasks.parent', args: const {});
  await stem.enqueue('tasks.invocation_parent', args: const {});
  final directTaskId = await childDefinition.enqueueWith(
    stem,
    const ChildArgs('direct-call'),
  );
  final directResult = await childDefinition.waitFor(
    stem,
    directTaskId,
    timeout: const Duration(seconds: 1),
  );
  // Example output keeps the script runnable without adding logging setup.
  // ignore: avoid_print
  print('[direct] result=${directResult?.value}');

  final inlineResult = await childDefinition.enqueueAndWaitWith(
    stem,
    const ChildArgs('inline-wait'),
    timeout: const Duration(seconds: 1),
  );
  // Example output keeps the script runnable without adding logging setup.
  // ignore: avoid_print
  print('[inline] result=${inlineResult?.value}');

  await Future<void>.delayed(const Duration(seconds: 1));
  await worker.shutdown();
  await backend.close();
  await broker.close();
}
