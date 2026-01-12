// Failure path example for quick start documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';

// #region quickstart-email-failure
class EmailReceiptTask extends TaskHandler<void> {
  @override
  String get name => 'billing.email-receipt';

  @override
  TaskOptions get options => const TaskOptions(
    queue: 'emails',
    maxRetries: 3,
    priority: 9,
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'customer@example.com';
    if (context.attempt < 2) {
      throw StateError('Simulated failure for $to');
    }
    print('[billing.email-receipt] delivered on attempt ${context.attempt}');
  }
}
// #endregion quickstart-email-failure

Future<void> main() async {
  final app = await StemApp.inMemory(tasks: [EmailReceiptTask()]);
  await app.start();

  final taskId = await app.stem.enqueue(
    'billing.email-receipt',
    args: {'to': 'demo@example.com'},
  );
  final result = await app.stem.waitForTask<void>(
    taskId,
    timeout: const Duration(seconds: 5),
  );
  print('Task state: ${result?.status.state}');

  await app.close();
}
