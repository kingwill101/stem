// Troubleshooting snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region troubleshooting-task
class EchoTask extends TaskHandler<String> {
  @override
  String get name => 'debug.echo';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final message = args['message'] as String? ?? 'hello';
    print('echo: $message');
    return message;
  }
}
// #endregion troubleshooting-task

Future<void> runTroubleshootingDemo() async {
  // #region troubleshooting-bootstrap
  final app = await StemApp.inMemory(
    tasks: [EchoTask()],
    workerConfig: const StemWorkerConfig(
      queue: 'default',
      consumerName: 'troubleshooting-worker',
      concurrency: 1,
    ),
  );
  unawaited(app.start());
  // #endregion troubleshooting-bootstrap

  // #region troubleshooting-enqueue
  final taskId = await app.stem.enqueue(
    'debug.echo',
    args: {'message': 'troubleshooting'},
  );
  // #endregion troubleshooting-enqueue

  // #region troubleshooting-results
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final result = await app.backend.get(taskId);
  print('Result: ${result?.payload}');
  // #endregion troubleshooting-results

  await app.shutdown();
}

Future<void> main() async {
  await runTroubleshootingDemo();
}
