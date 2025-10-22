import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/control/in_memory_revoke_store.dart';
import 'package:stem/stem.dart';

void main() {
  group('worker stats', () {
    test('prints snapshot for idle worker', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry();
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-test',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['worker', 'stats', '--worker', 'worker-test'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(code, equals(0));
      final output = out.toString();
      expect(output, contains('worker-test (ok)'));
      expect(output, contains('inflight: 0'));
      expect(output, contains('active: none'));
      expect(output, contains('subscribed queues: default'));
      expect(err.toString().trim(), isEmpty);

      await worker.shutdown();
      broker.dispose();
    });

    test('shutdown command triggers worker shutdown', () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(_BlockingTask(started, release));

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-cli-shutdown',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
      );
      await stem.enqueue('tasks.blocking');
      await started.future;

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        [
          'worker',
          'shutdown',
          '--worker',
          'worker-cli-shutdown',
          '--mode',
          'soft',
        ],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          revokeStore: InMemoryRevokeStore(),
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(code, equals(0));
      expect(out.toString(), contains('worker-cli-shutdown'));
      expect(out.toString(), contains('initiated'));

      release.complete();
      await worker.shutdown();
      broker.dispose();
    });

    test('includes active task metadata', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final started = Completer<void>();
      final release = Completer<void>();
      final registry = SimpleTaskRegistry()
        ..register(_BlockingTask(started, release));

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-active',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
      );
      await stem.enqueue('tasks.blocking');

      await started.future;

      final out = StringBuffer();
      final err = StringBuffer();

      try {
        final code = await runStemCli(
          ['worker', 'stats', '--worker', 'worker-active'],
          out: out,
          err: err,
          contextBuilder: () async => CliContext(
            broker: broker,
            backend: backend,
            routing: RoutingRegistry(RoutingConfig.legacy()),
            dispose: () async {},
          ),
        );

        expect(code, equals(0));
        final output = out.toString();
        expect(output, contains('worker-active (ok)'));
        expect(output, contains('active (1):'));
        expect(output, contains('tasks.blocking'));
        expect(output, contains('queue=default'));
        expect(output, contains('subscribed queues: default'));
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
        await worker.shutdown();
        broker.dispose();
      }
    });
  });

  group('worker inspect and revoke', () {
    test('inspect returns active task snapshot', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final revokeStore = InMemoryRevokeStore();
      final started = Completer<void>();
      final release = Completer<void>();
      final registry = SimpleTaskRegistry()
        ..register(_BlockingTask(started, release));

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-inspect',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
      );
      await stem.enqueue('tasks.blocking');

      await started.future;

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['worker', 'inspect', '--worker', 'worker-inspect', '--json'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          revokeStore: revokeStore,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(code, equals(0));
      final output = out.toString();
      expect(output, contains('worker-inspect'));
      expect(output, contains('"active"'));

      release.complete();
      await worker.shutdown();
      broker.dispose();
    });

    test('revoke persists entries and notifies workers', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final revokeStore = InMemoryRevokeStore();
      final registry = SimpleTaskRegistry();

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-revoke',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );

      await worker.start();

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['worker', 'revoke', '--worker', 'worker-revoke', '--task', 'task-1'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          revokeStore: revokeStore,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(code, equals(0));
      expect(out.toString(), contains('worker-revoke'));
      final records = await revokeStore.list('stem');
      expect(records.any((entry) => entry.taskId == 'task-1'), isTrue);

      await worker.shutdown();
      broker.dispose();
    });

    test('revoke terminate cancels inline task', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final revokeStore = InMemoryRevokeStore();
      final started = Completer<void>();
      final registry = SimpleTaskRegistry()..register(_LoopingTask(started));

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-term',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
      );
      final taskId = await stem.enqueue('tasks.looping');

      await started.future;

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        [
          'worker',
          'revoke',
          '--worker',
          'worker-term',
          '--task',
          taskId,
          '--terminate',
        ],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          revokeStore: revokeStore,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(code, equals(0));

      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.revoked &&
              event.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.cancelled);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });
  });
}

class _BlockingTask implements TaskHandler<void> {
  _BlockingTask(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  String get name => 'tasks.blocking';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
  }
}

class _LoopingTask implements TaskHandler<void> {
  _LoopingTask(this.started);

  final Completer<void> started;

  @override
  String get name => 'tasks.looping';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    started.complete();
    while (true) {
      context.heartbeat();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}
