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

Future<(Stem, Worker, InMemoryResultBackend)> _bootstrap() async {
  // #region troubleshooting-bootstrap
  final registry = SimpleTaskRegistry()..register(EchoTask());
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'default',
    consumerName: 'troubleshooting-worker',
    concurrency: 1,
  );
  unawaited(worker.start());

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  // #endregion troubleshooting-bootstrap

  return (stem, worker, backend);
}

Future<void> runTroubleshootingDemo() async {
  final (stem, worker, backend) = await _bootstrap();

  // #region troubleshooting-enqueue
  final taskId = await stem.enqueue(
    'debug.echo',
    args: {'message': 'troubleshooting'},
  );
  // #endregion troubleshooting-enqueue

  // #region troubleshooting-results
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final result = await backend.get(taskId);
  print('Result: ${result?.value}');
  // #endregion troubleshooting-results

  await worker.shutdown();
}

Future<void> main() async {
  await runTroubleshootingDemo();
}
