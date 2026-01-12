// First steps snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region first-steps-task
class EmailTask extends TaskHandler<String> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'anonymous';
    return 'sent to $to';
  }
}
// #endregion first-steps-task

// #region first-steps-run
Future<void> runInMemoryDemo() async {
  // #region first-steps-bootstrap
  final app = await StemApp.inMemory(
    tasks: [EmailTask()],
    workerConfig: const StemWorkerConfig(
      queue: 'default',
      consumerName: 'first-steps-worker',
    ),
  );
  await app.start();
  // #endregion first-steps-bootstrap

  // #region first-steps-enqueue
  final taskId = await app.stem.enqueue(
    'email.send',
    args: {'to': 'hello@example.com'},
  );
  print('Enqueued $taskId');
  // #endregion first-steps-enqueue

  // #region first-steps-results
  final result = await app.stem.waitForTask<String>(taskId);
  print('Task state: ${result?.status.state} value=${result?.value}');
  // #endregion first-steps-results

  await app.close();
}
// #endregion first-steps-run

Future<void> main() async {
  await runInMemoryDemo();
}
