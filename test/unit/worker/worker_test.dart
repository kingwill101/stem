import 'dart:async';
import 'dart:convert';

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
