import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_task_context_mixed_example/shared.dart';

Future<void> main(List<String> args) async {
  final tasks = buildTasks();
  final client = await StemClient.create(
    broker: StemBrokerFactory(create: connectBroker),
    backend: StemBackendFactory.inMemory(),
    tasks: tasks,
  );

  final forceFail = args.contains('--fail');
  final overwrite = args.contains('--overwrite');
  final runId = DateTime.now().millisecondsSinceEpoch.toString();

  final taskId = overwrite ? 'task-context-mixed' : null;
  final firstId = await client.enqueue(
    'demo.inline_parent',
    args: {'runId': runId, 'forceFail': forceFail},
    enqueueOptions: TaskEnqueueOptions(taskId: taskId, queue: mixedQueue),
  );
  stdout.writeln(
    'Enqueued demo.inline_parent id=$firstId runId=$runId forceFail=$forceFail',
  );

  if (overwrite) {
    final overwriteId = await client.enqueue(
      'demo.inline_parent',
      args: {'runId': '${runId}_overwrite', 'forceFail': forceFail},
      enqueueOptions: TaskEnqueueOptions(taskId: taskId, queue: mixedQueue),
    );
    stdout.writeln('Overwrote task id=$overwriteId');
  }

  await client.close();
}
