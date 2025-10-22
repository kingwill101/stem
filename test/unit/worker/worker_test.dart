import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:stem/stem.dart';
import 'package:stem/src/control/in_memory_revoke_store.dart';
import 'package:stem/src/control/revoke_store.dart';

void main() {
  group('Worker', () {
    test('executes task and records success', () async {
      final broker = InMemoryBroker(
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

    test('autoscaler scales concurrency up and down', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.autoscale',
            entrypoint: _autoscaleEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-autoscale',
        concurrency: 4,
        prefetchMultiplier: 1,
        autoscale: const WorkerAutoscaleConfig(
          enabled: true,
          minConcurrency: 1,
          maxConcurrency: 4,
          scaleUpStep: 1,
          scaleDownStep: 1,
          backlogPerIsolate: 1.0,
          tick: Duration(milliseconds: 40),
          idlePeriod: Duration(milliseconds: 120),
          scaleUpCooldown: Duration(milliseconds: 40),
          scaleDownCooldown: Duration(milliseconds: 40),
        ),
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );
      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      for (var i = 0; i < 6; i++) {
        await stem.enqueue('tasks.autoscale');
      }

      await _waitFor(
        () => worker.activeConcurrency >= 3,
        timeout: const Duration(seconds: 2),
      );
      expect(worker.activeConcurrency, greaterThanOrEqualTo(3));

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            6,
        timeout: const Duration(seconds: 5),
      );

      await _waitFor(
        () => worker.activeConcurrency == 1,
        timeout: const Duration(seconds: 10),
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('consumes tasks across multiple subscribed queues', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.default',
            entrypoint: (context, args) async {
              return;
            },
            options: const TaskOptions(maxRetries: 1),
          ),
        )
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.priority',
            entrypoint: (context, args) async {
              return;
            },
            options: const TaskOptions(queue: 'priority', maxRetries: 1),
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        subscription: RoutingSubscription(
          queues: const ['default', 'priority'],
        ),
        consumerName: 'worker-multi',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      expect(worker.subscriptionQueues, containsAll(['default', 'priority']));

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.default');
      await stem.enqueue(
        'tasks.priority',
        options: const TaskOptions(queue: 'priority'),
      );

      await _waitFor(
        () =>
            events.where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 5),
      );

      final completedQueues = events
          .where((event) => event.type == WorkerEventType.completed)
          .map((event) => event.envelope?.queue)
          .whereType<String>()
          .toSet();

      expect(completedQueues, contains('default'));
      expect(completedQueues, contains('priority'));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('warm shutdown drains tasks', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.sleepy',
            entrypoint: _sleepyEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-warm-shutdown',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );
      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.sleepy');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      await worker.shutdown(mode: WorkerShutdownMode.warm);

      expect(
        events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == taskId,
        ),
        isTrue,
      );
      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      await sub.cancel();
      broker.dispose();
    });

    test('max tasks per isolate triggers recycle', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.recycle',
            entrypoint: _isolateHashEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-recycle',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
          maxTasksPerIsolate: 1,
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final first = await stem.enqueue('tasks.recycle');
      final second = await stem.enqueue('tasks.recycle');

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 3),
      );

      final firstStatus = await backend.get(first);
      final secondStatus = await backend.get(second);
      expect(firstStatus?.payload, isNotNull);
      expect(secondStatus?.payload, isNotNull);
      expect(firstStatus?.payload, isNot(equals(secondStatus?.payload)));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('memory recycle threshold replaces isolate', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.memory-recycle',
            entrypoint: _isolateHashEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-memory-recycle',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
          maxMemoryPerIsolateBytes: 1,
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final first = await stem.enqueue('tasks.memory-recycle');
      final second = await stem.enqueue('tasks.memory-recycle');

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 3),
      );

      final firstStatus = await backend.get(first);
      final secondStatus = await backend.get(second);
      expect(firstStatus?.payload, isNotNull);
      expect(secondStatus?.payload, isNotNull);
      expect(firstStatus?.payload, isNot(equals(secondStatus?.payload)));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('verifies signed tasks succeed end-to-end', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('signing-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      final producerSigner = PayloadSigner(signingConfig);
      final verifierSigner = PayloadSigner(signingConfig);

      final workerEvents = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-signed',
        concurrency: 1,
        prefetchMultiplier: 1,
        signer: verifierSigner,
      );
      final sub = worker.events.listen(workerEvents.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
        signer: producerSigner,
      );

      final taskId = await stem.enqueue('tasks.success');

      await _waitFor(
        () => workerEvents.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      final dead = await broker.listDeadLetters('default');
      expect(dead.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('routes tampered signatures to dead letters', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('signing-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      final producerSigner = PayloadSigner(signingConfig);
      final verifierSigner = PayloadSigner(signingConfig);

      final workerEvents = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-signed-invalid',
        concurrency: 1,
        prefetchMultiplier: 1,
        signer: verifierSigner,
      );
      final sub = worker.events.listen(workerEvents.add);

      await worker.start();

      final envelope = Envelope(name: 'tasks.success', args: const {});
      final signed = await producerSigner.sign(envelope);
      final tampered = signed.copyWith(args: const {'tampered': true});
      await broker.publish(tampered);

      await _waitFor(
        () => workerEvents.any(
          (event) =>
              event.type == WorkerEventType.failed &&
              event.envelope?.id == tampered.id,
        ),
      );

      final status = await backend.get(tampered.id);
      expect(status?.state, TaskState.failed);

      final dead = await broker.listDeadLetters('default');
      expect(dead.entries, hasLength(1));
      expect(dead.entries.single.envelope.id, tampered.id);
      expect(dead.entries.single.reason, equals('signature-invalid'));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('retries failing task then succeeds', () async {
      final broker = InMemoryBroker(
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

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('moves task to dead letter after max retries', () async {
      final broker = InMemoryBroker(
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

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, hasLength(1));
      expect(deadPage.entries.single.envelope.id, equals(taskId));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('executes handler inside isolate when entrypoint provided', () async {
      final broker = InMemoryBroker(
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
      final broker = InMemoryBroker(
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

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('skips revoked tasks from persistent store', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
      final revokeStore = InMemoryRevokeStore();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
      );

      final taskId = await stem.enqueue('tasks.success');
      await revokeStore.upsertAll([
        RevokeEntry(
          namespace: 'stem',
          taskId: taskId,
          version: generateRevokeVersion(),
          issuedAt: DateTime.now().toUtc(),
          terminate: true,
        ),
      ]);

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        queue: 'default',
        consumerName: 'worker-revoked',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

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

FutureOr<Object?> _autoscaleEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  return null;
}

FutureOr<Object?> _sleepyEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return null;
}

FutureOr<int> _isolateHashEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  return Isolate.current.hashCode;
}
