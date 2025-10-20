import 'dart:async';

import 'package:test/test.dart';
import 'package:untitled6/untitled6.dart';
import 'package:untitled6/src/broker_redis/in_memory_broker.dart';

void main() {
  group('Worker', () {
    test('executes task and records success', () async {
      final broker = InMemoryRedisBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-1',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.success');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final running = await backend.get(taskId);
      expect(running?.state, isNotNull);

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final event = events.firstWhere(
        (e) => e.type == WorkerEventType.completed && e.envelope?.id == taskId,
      );

      expect(event.envelope?.id, equals(taskId));
      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('retries failing task then succeeds', () async {
      final broker = InMemoryRedisBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_FlakyTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-2',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.flaky');

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );
      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.attempt, equals(1));

      expect(
        events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
        isTrue,
      );

      expect(broker.deadLetters('default'), isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('moves task to dead letter after max retries', () async {
      final broker = InMemoryRedisBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_AlwaysFailTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-3',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.fail');

      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.failed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.failed);

      final dead = broker.deadLetters('default');
      expect(dead, hasLength(1));
      expect(dead.single.envelope.id, equals(taskId));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('executes handler inside isolate when entrypoint provided', () async {
      final broker = InMemoryRedisBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.isolate',
            entrypoint: _isolateEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-isolate',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.isolate', args: {'value': 7});

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.payload, equals(14));

      expect(
        events.any((e) => e.type == WorkerEventType.progress),
        isTrue,
        reason: 'expected isolate task to emit progress',
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('enforces hard time limit for isolate tasks', () async {
      final broker = InMemoryRedisBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<String>(
            name: 'tasks.hard-limit',
            entrypoint: _hardLimitEntrypoint,
            options: const TaskOptions(
              maxRetries: 1,
              hardTimeLimit: Duration(milliseconds: 30),
            ),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-timeout',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.hard-limit');

      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
      );
      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final retryEvent = events.firstWhere(
        (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
      );
      expect(retryEvent.error, isA<TimeoutException>());

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.attempt, equals(1));

      expect(broker.deadLetters('default'), isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });
  });
}

class _SuccessTask implements TaskHandler<String> {
  @override
  String get name => 'tasks.success';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    context.heartbeat();
    return 'ok';
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

class _FlakyTask implements TaskHandler<void> {
  int _attempts = 0;

  @override
  String get name => 'tasks.flaky';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (_attempts == 0) {
      _attempts++;
      throw StateError('first attempt fails');
    }
    context.progress(1.0);
  }
}

class _AlwaysFailTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.fail';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 1);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    throw StateError('always fails');
  }
}

FutureOr<Object?> _isolateEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  context.heartbeat();
  await context.progress(0.5);
  return (args['value'] as int) * 2;
}

FutureOr<Object?> _hardLimitEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  if (context.attempt == 0) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  return 'done';
}
