import 'dart:convert';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  setUp(StemMetrics.instance.reset);

  test('effects phase write is the boundary before settlement', () async {
    final broker = _FaultBroker();
    final backend = _FaultBackend(rejectEffectsOnce: true);
    final task = _FailingTerminalTask();
    addTearDown(broker.close);
    addTearDown(backend.close);
    final envelope = Envelope(
      name: task.name,
      args: const {'value': 7},
      headers: const {'x-original': 'header'},
      meta: const {'x-original': 'meta'},
    );

    await broker.publish(envelope);
    final first = await _run(broker, backend, task);
    expect(first.reason, WorkerRunStopReason.failed);
    expect(task.calls, 1);
    expect(task.finalizations, 1);
    expect(broker.settlementAttempts, 0);
    expect(broker.deadLetterAttempts, 0);
    expect(await broker.inflightCount('default'), 1);
    final status = await backend.get(envelope.id);
    expect(
      status!.meta['stem.terminalFailureEnvelope'],
      isA<Map<String, Object?>>(),
    );
    expect(
      (status.meta['stem.terminalFailureEnvelope']!
          as Map<String, Object?>)['state'],
      'pending',
    );

    // Explicitly requeue the owned receipt, without manufacturing a duplicate.
    await broker.redeliver();
    final second = await _run(broker, backend, task);
    expect(second.reason, isNot(WorkerRunStopReason.failed));
    expect(task.calls, 1);
    expect(task.finalizations, 2);
    expect(broker.deadLetterAttempts, 1);
    expect(await broker.inflightCount('default'), 0);
    _expectDoneMarker(await backend.get(envelope.id), envelope, 'dead-letter');
    // The phase was not durable, so effects remain at-least-once.
    expect(_metric('stem.tasks.failed'), 2);
  });

  test(
    'effects-complete recovery skips effects after settlement failure',
    () async {
      final broker = _FaultBroker(rejectSettlementOnce: true);
      final backend = _FaultBackend();
      final task = _RetryTerminalTask();
      addTearDown(broker.close);
      addTearDown(backend.close);
      final envelope = Envelope(name: task.name, args: const {});
      await broker.publish(envelope);
      expect(
        (await _run(broker, backend, task)).reason,
        WorkerRunStopReason.failed,
      );
      expect(task.finalizations, 1);
      expect(broker.settlementAttempts, 1);
      expect(await broker.inflightCount('default'), 1);
      _expectPhase(await backend.get(envelope.id), 'effects-complete');
      expect(_metric('stem.tasks.failed'), 1);

      await broker.redeliver();
      // Simulate deployment after removing the task entirely.
      await _run(broker, backend, null);
      expect(task.finalizations, 1, reason: 'effects must not repeat');
      expect(broker.settlementAttempts, 2);
      expect(await broker.inflightCount('default'), 0);
      _expectDoneMarker(
        await backend.get(envelope.id),
        envelope,
        'nack',
      );
      expect(_metric('stem.tasks.failed'), 1);
    },
  );

  test(
    'done write failure retries settlement and done without effects',
    () async {
      final broker = _FaultBroker();
      final backend = _FaultBackend(rejectDoneOnce: true);
      final task = _RetryTerminalTask();
      addTearDown(broker.close);
      addTearDown(backend.close);
      final envelope = Envelope(name: task.name, args: const {});
      await broker.publish(envelope);

      expect(
        (await _run(broker, backend, task)).reason,
        WorkerRunStopReason.failed,
      );
      expect(task.finalizations, 1);
      expect(broker.settlementAttempts, 1);
      expect(await broker.inflightCount('default'), 0);
      _expectPhase(await backend.get(envelope.id), 'effects-complete');

      // The original delivery was settled successfully. This duplicate models
      // a later duplicate after settlement, not an unexpired second receipt.
      await broker.publish(envelope);
      await _run(broker, backend, task);
      expect(task.finalizations, 1);
      expect(broker.settlementAttempts, 2);
      _expectDoneMarker(
        await backend.get(envelope.id),
        envelope,
        'nack',
      );
    },
  );

  for (final action in ['nack', 'dead-letter']) {
    test(
      'terminal action $action preserves retry/dead-letter behavior',
      () async {
        final broker = _FaultBroker();
        final backend = _FaultBackend();
        final task = action == 'nack'
            ? _RetryTerminalTask()
            : _FailingTerminalTask();
        addTearDown(broker.close);
        addTearDown(backend.close);
        final envelope = Envelope(name: task.name, args: const {});
        await broker.publish(envelope);

        await _run(broker, backend, task);
        expect(task.calls, 1);
        expect(task.finalizations, 1);
        expect(
          action == 'nack'
              ? broker.settlementAttempts
              : broker.deadLetterAttempts,
          1,
        );
        if (action == 'dead-letter') {
          expect(
            (await broker.listDeadLetters('default')).entries,
            hasLength(1),
          );
        } else {
          expect(broker.nackSettlements, 1);
        }
        _expectDoneMarker(await backend.get(envelope.id), envelope, action);
      },
    );
  }

  test('done recovery acknowledges after the task is removed', () async {
    final broker = _FaultBroker();
    final backend = _FaultBackend();
    final task = _RetryTerminalTask();
    addTearDown(broker.close);
    addTearDown(backend.close);
    final envelope = Envelope(name: task.name, args: const {});
    await broker.publish(envelope);
    await _run(broker, backend, task);
    _expectPhase(await backend.get(envelope.id), 'done');

    await broker.publish(envelope);
    await _run(broker, backend, null);
    expect(task.calls, 1);
    expect(task.finalizations, 1);
    expect(broker.nackSettlements, 1);
    expect(broker.deadLetterAttempts, 0);
    expect(broker.settlementAttempts, 2);
    expect(await broker.inflightCount('default'), 0);
  });

  test(
    'removed-task recovery still requires an authenticated delivery',
    () async {
      final broker = _FaultBroker(rejectSettlementOnce: true);
      final backend = _FaultBackend();
      final task = _RetryTerminalTask();
      addTearDown(broker.close);
      addTearDown(backend.close);
      final envelope = Envelope(name: task.name, args: const {});
      await broker.publish(envelope);
      expect(
        (await _run(broker, backend, task)).reason,
        WorkerRunStopReason.failed,
      );
      _expectPhase(await backend.get(envelope.id), 'effects-complete');

      final signer = PayloadSigner(
        SigningConfig.fromEnvironment({
          'STEM_SIGNING_KEYS': 'test:${base64.encode(List<int>.filled(32, 1))}',
          'STEM_SIGNING_ACTIVE_KEY': 'test',
        }),
      );
      await broker.redeliver();
      await _run(broker, backend, null, signer: signer);
      _expectPhase(await backend.get(envelope.id), 'effects-complete');
      expect(task.finalizations, 1);

      await broker.publish(await signer.sign(envelope));
      await _run(broker, backend, null, signer: signer);
      _expectPhase(await backend.get(envelope.id), 'done');
      expect(task.calls, 1);
      expect(task.finalizations, 1);
      expect(await broker.inflightCount('default'), 0);
    },
  );

  test('callback failure leaves pending marker and retries callback', () async {
    final broker = _FaultBroker();
    final backend = _FaultBackend();
    final task = _CallbackFailsOnceTask();
    addTearDown(broker.close);
    addTearDown(backend.close);
    final envelope = Envelope(name: task.name, args: const {});
    await broker.publish(envelope);

    expect(
      (await _run(broker, backend, task)).reason,
      WorkerRunStopReason.failed,
    );
    expect(task.finalizations, 1);
    expect(broker.settlementAttempts, 0);
    expect(await broker.inflightCount('default'), 1);
    _expectPhase(await backend.get(envelope.id), 'pending');

    final status = (await backend.get(envelope.id))!;
    await backend.set(
      status.id,
      status.state,
      payload: status.payload,
      error: status.error,
      attempt: status.attempt,
      meta: {
        ...status.meta,
        'stem.terminalFailureEnvelope': {
          ...(status.meta['stem.terminalFailureEnvelope']! as Map)
              .cast<String, Object?>(),
          'future-field': 'preserve-me',
        },
      },
    );
    await broker.redeliver();
    await _run(broker, backend, task);
    expect(task.finalizations, 2);
    expect(broker.settlementAttempts, 1);
    _expectDoneMarker(await backend.get(envelope.id), envelope, 'dead-letter');
    expect(
      ((await backend.get(envelope.id))!.meta['stem.terminalFailureEnvelope']!
          as Map)['future-field'],
      'preserve-me',
    );
    expect(await broker.inflightCount('default'), 0);
  });
}

Future<WorkerRunOutcome> _run(
  QueueBroker broker,
  ResultBackend backend,
  TaskHandler<void>? task, {
  PayloadSigner? signer,
}) =>
    Worker(
      broker: broker,
      backend: backend,
      tasks: [?task],
      signer: signer,
      concurrency: 1,
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
    ).runUntilIdle(
      budget: const Duration(seconds: 3),
      shutdownReserve: const Duration(milliseconds: 1),
      idleTimeout: const Duration(milliseconds: 10),
    );

void _expectPhase(TaskStatus? status, String phase) {
  expect(status, isNotNull);
  final marker =
      status!.meta['stem.terminalFailureEnvelope']! as Map<String, Object?>;
  expect(marker['state'], phase);
}

void _expectDoneMarker(TaskStatus? status, Envelope envelope, String action) {
  _expectPhase(status, 'done');
  final marker =
      status!.meta['stem.terminalFailureEnvelope']! as Map<String, Object?>;
  expect(marker['action'], action);
  expect(marker['envelope'], envelope.toJson());
  expect(marker['context'], isA<Map<String, Object?>>());
}

int _metric(String name) {
  final counters = StemMetrics.instance.snapshot()['counters']! as List;
  final matches = counters.where((entry) => (entry as Map)['name'] == name);
  return matches.fold<int>(
    0,
    (sum, entry) => sum + ((entry as Map)['value'] as num).toInt(),
  );
}

class _FaultBackend extends InMemoryResultBackend {
  _FaultBackend({
    this.rejectEffectsOnce = false,
    this.rejectDoneOnce = false,
  });
  bool rejectEffectsOnce;
  bool rejectDoneOnce;

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) {
    final original = meta['stem.terminalFailureEnvelope'];
    final lifecycle = original is Map ? original['state'] : null;
    if (lifecycle == 'effects-complete' && rejectEffectsOnce) {
      rejectEffectsOnce = false;
      throw StateError('effects phase unavailable');
    }
    if (lifecycle == 'done' && rejectDoneOnce) {
      rejectDoneOnce = false;
      throw StateError('done phase unavailable');
    }
    return super.set(
      taskId,
      state,
      payload: payload,
      error: error,
      attempt: attempt,
      meta: meta,
      ttl: ttl,
    );
  }
}

class _FaultBroker extends InMemoryBroker {
  _FaultBroker({this.rejectSettlementOnce = false})
    : super(
        defaultVisibilityTimeout: const Duration(days: 1),
      );
  bool rejectSettlementOnce;
  int settlementAttempts = 0;
  int nackSettlements = 0;
  int deadLetterAttempts = 0;
  Delivery? lastDelivery;

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => super
      .consume(
        subscription,
        prefetch: prefetch,
        consumerGroup: consumerGroup,
        consumerName: consumerName,
      )
      .map((delivery) {
        lastDelivery = delivery;
        return delivery;
      });

  Future<void> redeliver() => super.nack(lastDelivery!);

  void _checkSettlement() {
    settlementAttempts++;
    if (rejectSettlementOnce) {
      rejectSettlementOnce = false;
      throw StateError('settlement unavailable');
    }
  }

  @override
  Future<void> ack(Delivery delivery) async {
    _checkSettlement();
    await super.ack(delivery);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (!requeue) {
      _checkSettlement();
      nackSettlements++;
    }
    await super.nack(delivery, requeue: requeue);
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    deadLetterAttempts++;
    _checkSettlement();
    await super.deadLetter(delivery, reason: reason, meta: meta);
  }
}

class _FailingTerminalTask
    implements TaskHandler<void>, TaskTerminalFailureHandler {
  int calls = 0;
  int finalizations = 0;
  @override
  String get name => 'phase.failure';
  @override
  TaskOptions get options => const TaskOptions();
  @override
  TaskMetadata get metadata => const TaskMetadata();
  @override
  TaskEntrypoint? get isolateEntrypoint => null;
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls++;
    throw StateError('action failed');
  }

  @override
  Future<void> onTerminalFailure(Envelope envelope, TaskStatus status) async {
    finalizations++;
  }
}

class _RetryTerminalTask extends _FailingTerminalTask {
  @override
  String get name => 'phase.retry';
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls++;
    throw TaskRetryRequest(maxRetries: 0);
  }
}

class _CallbackFailsOnceTask extends _FailingTerminalTask {
  @override
  Future<void> onTerminalFailure(Envelope envelope, TaskStatus status) async {
    finalizations++;
    if (finalizations == 1) throw StateError('callback unavailable');
  }
}
