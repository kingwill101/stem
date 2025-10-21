import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../support/inline_task_handler.dart';

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for condition.');
}

void main() {
  test('soak: processes extended workload without errors', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final completed = <int>{};

    final registry = SimpleTaskRegistry()
      ..register(
        InlineTaskHandler<void>(
          name: 'soak.task',
          onCall: (context, args) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            completed.add(args['index'] as int);
          },
        ),
      );

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'soak-worker',
      concurrency: 4,
      heartbeatTransport: const NoopHeartbeatTransport(),
    );

    await worker.start();

    const total = 500;
    for (var i = 0; i < total; i++) {
      await stem.enqueue('soak.task', args: {'index': i});
    }

    await _waitFor(
      () async => completed.length == total,
      timeout: const Duration(seconds: 30),
    );

    await worker.shutdown();
    broker.dispose();

    expect(completed.length, equals(total));
  }, tags: ['soak']);
}
