import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../support/inline_task_handler.dart';

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}

void main() {
  test('processes 200 tasks within throughput target', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final completed = <int>{};

    final registry = SimpleTaskRegistry()
      ..register(
        InlineTaskHandler<void>(
          name: 'perf.echo',
          onCall: (context, args) {
            completed.add(args['index'] as int);
          },
        ),
      );

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'perf-worker',
      concurrency: 8,
      heartbeatTransport: const NoopHeartbeatTransport(),
    );

    await worker.start();
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < 200; i++) {
      await stem.enqueue('perf.echo', args: {'index': i});
    }

    await _waitFor(
      () async => completed.length == 200,
      timeout: const Duration(seconds: 10),
    );

    stopwatch.stop();
    // Target: 200 tasks should finish within 3 seconds on in-memory broker.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));

    await worker.shutdown();
    broker.dispose();
  });
}
