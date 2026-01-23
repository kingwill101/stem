// Best practices snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

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
Future<void> enqueueTyped(Stem stem) async {
  await stem.enqueue(
    'orders.sync',
    args: {'orderId': 'order-42'},
    meta: {'requestId': 'req-001'},
  );
}
// #endregion best-practices-enqueue

Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(IdempotentTask());
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final stem = Stem(broker: broker, registry: registry, backend: backend);

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'default',
  );
  unawaited(worker.start());

  await enqueueTyped(stem);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await worker.shutdown();
  await broker.close();
  await backend.close();
}
