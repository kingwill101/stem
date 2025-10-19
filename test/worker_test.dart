import 'dart:async';

import 'package:test/test.dart';
import 'package:untitled6/untitled6.dart';
import 'package:untitled6/src/backend_redis/redis_backend.dart';
import 'package:untitled6/src/broker_redis/redis_broker.dart';

void main() {
  group('Worker', () {
    test('executes task and records success', () async {
      final broker = RedisStreamsBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = RedisResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-1',
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
      final broker = RedisStreamsBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = RedisResultBackend();
      final registry = SimpleTaskRegistry()..register(_FlakyTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-2',
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
      final broker = RedisStreamsBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = RedisResultBackend();
      final registry = SimpleTaskRegistry()..register(_AlwaysFailTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-3',
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
  });
}

class _SuccessTask implements TaskHandler<String> {
  @override
  String get name => 'tasks.success';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

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
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    throw StateError('always fails');
  }
}
