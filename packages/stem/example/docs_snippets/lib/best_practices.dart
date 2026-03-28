// Best practices snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';

// #region best-practices-task
class IdempotentTask extends TaskHandler<void> {
  @override
  String get name => 'orders.sync';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskMetadata get metadata => const TaskMetadata(idempotent: true);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final orderId = args['orderId'] as String? ?? 'unknown';
    print('Sync order $orderId');
  }
}
// #endregion best-practices-task

// #region best-practices-enqueue
Future<void> enqueueTyped(TaskEnqueuer enqueuer) async {
  await enqueuer.enqueue(
    'orders.sync',
    args: {'orderId': 'order-42'},
    meta: {'requestId': 'req-001'},
  );
}
// #endregion best-practices-enqueue

Future<void> main() async {
  final app = await StemApp.inMemory(
    tasks: [IdempotentTask()],
  );

  await enqueueTyped(app);
  await app.close();
}
