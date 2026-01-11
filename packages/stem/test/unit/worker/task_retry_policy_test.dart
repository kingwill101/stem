import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('TaskRetryPolicy', () {
    test('uses task retry policy over worker default', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      const policy = TaskRetryPolicy(
        jitter: false,
        defaultDelay: Duration(milliseconds: 25),
      );
      final task = _PolicyFlakyTask(
        name: 'tasks.policy',
        options: const TaskOptions(maxRetries: 1, retryPolicy: policy),
      );
      final registry = SimpleTaskRegistry()..register(task);
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-policy',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 200),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.policy');

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.retried),
      );

      final retried = events.firstWhere(
        (event) => event.type == WorkerEventType.retried,
      );
      expect(retried.data?['retryDelayMs'], equals(25));

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.completed),
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('per-enqueue retry policy overrides handler policy', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      const handlerPolicy = TaskRetryPolicy(
        jitter: false,
        defaultDelay: Duration(milliseconds: 80),
      );
      const overridePolicy = TaskRetryPolicy(
        jitter: false,
        defaultDelay: Duration(milliseconds: 15),
      );
      final registry = SimpleTaskRegistry()
        ..register(
          _PolicyFlakyTask(
            name: 'tasks.override',
            options: const TaskOptions(
              maxRetries: 1,
              retryPolicy: handlerPolicy,
            ),
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-override',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 200),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue(
        'tasks.override',
        options: const TaskOptions(maxRetries: 1, retryPolicy: overridePolicy),
      );

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.retried),
      );

      final retried = events.firstWhere(
        (event) => event.type == WorkerEventType.retried,
      );
      expect(retried.data?['retryDelayMs'], equals(15));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('auto-retry filters suppress retries', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      const policy = TaskRetryPolicy(
        jitter: false,
        defaultDelay: Duration(milliseconds: 15),
        autoRetryFor: [StateError],
        dontAutoRetryFor: [ArgumentError],
      );
      final registry = SimpleTaskRegistry()
        ..register(
          _AlwaysErrorTask(
            name: 'tasks.filtered',
            options: const TaskOptions(maxRetries: 1, retryPolicy: policy),
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-filtered',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.filtered');

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.failed),
      );

      expect(
        events.any((event) => event.type == WorkerEventType.retried),
        isFalse,
      );
      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.failed));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('TaskContext.retry schedules a new attempt', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(_ExplicitRetryTask('tasks.explicit'));

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-explicit',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.explicit');

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.retried),
      );
      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.succeeded));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });
  });
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

class _PolicyFlakyTask implements TaskHandler<void> {
  _PolicyFlakyTask({required this.name, required this.options});

  @override
  final String name;

  @override
  final TaskOptions options;

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  int _attempt = 0;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (_attempt == 0) {
      _attempt += 1;
      throw StateError('first attempt fails');
    }
  }
}

class _AlwaysErrorTask implements TaskHandler<void> {
  _AlwaysErrorTask({required this.name, required this.options});

  @override
  final String name;

  @override
  final TaskOptions options;

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    throw ArgumentError('filtered error');
  }
}

class _ExplicitRetryTask implements TaskHandler<void> {
  _ExplicitRetryTask(this.name);

  @override
  final String name;

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  int _attempt = 0;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (_attempt == 0) {
      _attempt += 1;
      await context.retry(
        countdown: const Duration(milliseconds: 20),
      );
    }
  }
}
