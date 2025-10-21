import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/stem.dart';

void main() {
  test('worker status prints snapshot from context backend', () async {
    final backend = InMemoryResultBackend();
    await backend.setWorkerHeartbeat(
      WorkerHeartbeat(
        workerId: 'test-worker',
        namespace: 'stem',
        timestamp: DateTime.utc(2024, 1, 1, 12),
        isolateCount: 2,
        inflight: 1,
        queues: [QueueHeartbeat(name: 'default', inflight: 1)],
      ),
    );

    final broker = InMemoryBroker();
    final out = StringBuffer();
    final err = StringBuffer();

    final code = await runStemCli(
      ['worker', 'status', '--namespace', 'stem'],
      out: out,
      err: err,
      contextBuilder: () async => CliContext(
        broker: broker,
        backend: backend,
        routing: RoutingRegistry(RoutingConfig.legacy()),
        dispose: () async {
          broker.dispose();
        },
      ),
    );

    expect(code, equals(0));
    expect(out.toString(), contains('test-worker'));
    expect(out.toString(), contains('inflight=1'));
  });

  test('worker status supports json output', () async {
    final backend = InMemoryResultBackend();
    await backend.setWorkerHeartbeat(
      WorkerHeartbeat(
        workerId: 'json-worker',
        namespace: 'stem',
        timestamp: DateTime.utc(2024, 1, 1),
        isolateCount: 1,
        inflight: 0,
        queues: const [],
      ),
    );

    final broker = InMemoryBroker();
    final out = StringBuffer();
    final err = StringBuffer();

    final code = await runStemCli(
      ['worker', 'status', '--json'],
      out: out,
      err: err,
      contextBuilder: () async => CliContext(
        broker: broker,
        backend: backend,
        routing: RoutingRegistry(RoutingConfig.legacy()),
        dispose: () async {
          broker.dispose();
        },
      ),
    );

    expect(code, equals(0));
    expect(out.toString(), contains('json-worker'));
    expect(out.toString().trim().startsWith('{'), isTrue);
  });
}
