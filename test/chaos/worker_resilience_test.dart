import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../support/inline_task_handler.dart';

void main() {
  test('worker recovers from failure and reprocesses task', () async {
    final broker = InMemoryRedisBroker();
    final backend = InMemoryResultBackend();

    final succeeded = Completer<void>();

    final registry = SimpleTaskRegistry()
      ..register(
        InlineTaskHandler<void>(
          name: 'chaos.resilience',
          onCall: (context, _) async {
            if (context.attempt == 0) {
              throw StateError('simulated crash');
            }
            if (!succeeded.isCompleted) {
              succeeded.complete();
            }
          },
          options: const TaskOptions(maxRetries: 2),
        ),
      );

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'chaos-worker',
      heartbeatTransport: const NoopHeartbeatTransport(),
    );

    await worker.start();
    final taskId = await stem.enqueue('chaos.resilience');
    final statusStream = backend.watch(taskId);

    await succeeded.future.timeout(const Duration(seconds: 5));
    final finalStatus = await statusStream
        .firstWhere((status) => status.state == TaskState.succeeded)
        .timeout(const Duration(seconds: 5));

    expect(finalStatus.state, equals(TaskState.succeeded));

    await worker.shutdown();
    broker.dispose();
  });
}
