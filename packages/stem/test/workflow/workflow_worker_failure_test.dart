import 'dart:async';
import 'dart:convert';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  for (final exhaust in [false, true]) {
    test(
      'worker ${exhaust ? 'exhausts' : 'retries'} workflow errors',
      () async {
        final broker = InMemoryBroker();
        final backend = InMemoryResultBackend();
        final registry = InMemoryTaskRegistry();
        final store = InMemoryWorkflowStore();
        final runtime = WorkflowRuntime(
          stem: Stem(broker: broker, backend: backend, registry: registry),
          store: store,
          eventBus: InMemoryEventBus(store),
        );
        registry.register(runtime.workflowRunnerHandler());
        addTearDown(broker.dispose);
        addTearDown(runtime.dispose);
        var calls = 0;
        runtime.registerWorkflow(
          WorkflowScript<int>(
            name: 'fails',
            run: (context) async {
              calls++;
              expect((await store.get(context.runId))!.isTerminal, isFalse);
              if (exhaust || calls == 1) throw StateError('deliberate');
              return 42;
            },
          ).definition,
        );
        final id = await runtime.startWorkflow('fails');
        final waiting = runtime.waitForCompletion<int>(
          id,
          pollInterval: const Duration(milliseconds: 1),
        );
        final worker = Worker(
          broker: broker,
          backend: backend,
          registry: registry,
          queue: runtime.queue,
          concurrency: 1,
          retryStrategy: _ImmediateRetry(),
        );
        await _drain(worker);
        final result = await waiting.timeout(const Duration(seconds: 1));
        expect(calls, exhaust ? 6 : 2);
        expect(
          result!.status,
          exhaust ? WorkflowStatus.failed : WorkflowStatus.completed,
        );
        expect(result.timedOut, isFalse);
        if (exhaust) {
          expect(result.state.lastError?['error'], contains('deliberate'));
        } else {
          expect(result.state.result, 42);
        }
      },
    );
  }

  test(
    'lease conflict uses explicit retry budget, not terminal failure',
    () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry();
      final store = _ConflictingStore();
      final runtime = WorkflowRuntime(
        stem: Stem(broker: broker, backend: backend, registry: registry),
        store: store,
        eventBus: InMemoryEventBus(store),
        runLeaseDuration: Duration.zero,
      );
      registry.register(runtime.workflowRunnerHandler());
      addTearDown(broker.dispose);
      addTearDown(runtime.dispose);
      var calls = 0;
      runtime.registerWorkflow(
        WorkflowScript<int>(
          name: 'lease',
          run: (context) async {
            calls++;
            expect((await store.get(context.runId))!.isTerminal, isFalse);
            return 7;
          },
        ).definition,
      );
      // Start beyond the ordinary runner retry budget. Lease contention must
      // still be retried using TaskRetryRequest's larger budget.
      final id = await store.createRun(workflow: 'lease', params: {});
      final task = Envelope(
        name: workflowRunTaskName,
        queue: runtime.queue,
        args: {'runId': id},
        attempt: 5,
        maxRetries: 5,
      );
      await broker.publish(task);
      await _drain(
        Worker(
          broker: broker,
          backend: backend,
          registry: registry,
          queue: runtime.queue,
          concurrency: 1,
          retryStrategy: _ImmediateRetry(),
        ),
      );
      expect(store.claims, 2);
      expect(calls, 1);
      expect((await store.get(id))!.status, WorkflowStatus.completed);
      expect((await backend.get(task.id))!.attempt, 6);
    },
  );

  for (final redelivery in ['ordinary', 'expired', 'revoked']) {
    test(
      'terminal hook recovers $redelivery redelivery without rerunning handler',
      () async {
        final broker = _RecordingBroker();
        final backend = InMemoryResultBackend();
        final revokes = InMemoryRevokeStore();
        final task = _FinalizingTask();
        final envelope = Envelope(
          name: task.name,
          args: const {'original': true},
        );
        addTearDown(broker.dispose);
        addTearDown(revokes.close);
        await broker.publish(envelope);
        Worker worker() => Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          revokeStore: revokes,
          concurrency: 1,
        );
        final first = _drain(worker());
        await task.entered.future;
        expect((await backend.get(envelope.id))!.state, TaskState.failed);
        expect(broker.settled, 0);
        task.release.completeError(StateError('store unavailable'));
        final outcome = await first;
        expect(outcome.reason, WorkerRunStopReason.failed);
        expect(outcome.error, isStateError);
        expect(task.calls, 1);
        expect(broker.settled, 0);

        // Simulate transport redelivery after losing the first worker.
        task.fail = false;
        if (redelivery == 'revoked') {
          await revokes.upsertAll([
            RevokeEntry(
              namespace: 'stem',
              taskId: envelope.id,
              version: 1,
              issuedAt: DateTime.now(),
            ),
          ]);
        }
        await broker.publish(
          envelope.copyWith(
            args: const {'altered': true},
            meta: {
              if (redelivery == 'expired')
                'stem.expiresAt': DateTime.utc(2000).toIso8601String(),
            },
          ),
        );
        await _drain(worker());
        expect(task.calls, 1);
        expect(task.finalizations, 2);
        expect(task.finalizedArgs, everyElement({'original': true}));
        expect(broker.settled, 1);
      },
    );
  }

  test('signature rejection cannot forge a finalization callback', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final task = _FinalizingTask()..fail = false;
    final signer = PayloadSigner(
      SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS': 'test:${base64.encode(List<int>.filled(32, 1))}',
        'STEM_SIGNING_ACTIVE_KEY': 'test',
      }),
    );
    final original = Envelope(name: task.name, args: const {});
    final forged = original.copyWith(
      meta: {
        'stem.terminalFailureEnvelope': original.toJson(),
      },
    );
    addTearDown(broker.dispose);
    Worker worker() => Worker(
      broker: broker,
      backend: backend,
      tasks: [task],
      signer: signer,
      concurrency: 1,
    );
    await broker.publish(forged);
    await _drain(worker());
    expect((await backend.get(original.id))!.state, TaskState.failed);
    expect(
      (await backend.get(original.id))!.meta,
      isNot(contains('stem.terminalFailureEnvelope')),
    );
    // A subsequently authenticated duplicate still must not finalize an
    // execution failure: this task never entered its handler.
    await broker.publish(await signer.sign(forged));
    await _drain(worker());
    expect(task.calls, 0);
    expect(task.finalizations, 0);
  });
}

Future<WorkerRunOutcome> _drain(Worker worker) => worker.runUntilIdle(
  budget: const Duration(seconds: 3),
  shutdownReserve: const Duration(milliseconds: 100),
  idleTimeout: const Duration(milliseconds: 20),
);

class _ImmediateRetry implements RetryStrategy {
  @override
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace) =>
      Duration.zero;
}

class _ConflictingStore extends InMemoryWorkflowStore {
  int claims = 0;

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    if (++claims == 1) return false;
    return super.claimRun(
      runId,
      ownerId: ownerId,
      leaseDuration: leaseDuration,
    );
  }
}

class _FinalizingTask implements TaskHandler<void>, TaskTerminalFailureHandler {
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  int finalizations = 0;
  final finalizedArgs = <Map<String, Object?>>[];
  bool fail = true;

  @override
  String get name => 'finalizing';
  @override
  TaskOptions get options => const TaskOptions();
  @override
  TaskMetadata get metadata => const TaskMetadata();
  @override
  TaskEntrypoint? get isolateEntrypoint => null;
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls++;
    throw StateError('handler failed');
  }

  @override
  Future<void> onTerminalFailure(Envelope envelope, TaskStatus status) async {
    finalizations++;
    finalizedArgs.add(envelope.args);
    expect(status.error!.message, contains('handler failed'));
    if (fail) {
      entered.complete();
      await release.future;
    }
  }
}

class _RecordingBroker extends InMemoryBroker {
  int settled = 0;

  @override
  Future<void> ack(Delivery delivery) async {
    settled++;
    await super.ack(delivery);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    settled++;
    await super.nack(delivery, requeue: requeue);
  }
}
