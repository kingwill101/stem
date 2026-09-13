import 'dart:async';
import 'dart:convert';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'captured failure token cannot overwrite a newer same-owner completion',
    () async {
      final store = _GatedFailureStore();
      final fixture = _Fixture(store);
      addTearDown(fixture.close);
      addTearDown(() {
        if (!store.release.isCompleted) store.release.complete();
      });
      final runtime = fixture.runtime('same-owner');
      final runId = await store.createRun(workflow: 'fails', params: const {});
      final envelope = Envelope(
        name: workflowRunTaskName,
        queue: runtime.queue,
        args: {'runId': runId},
      );
      var failureSignals = 0;
      final signal = StemSignals.workflowRunFailed.connect((payload, _) {
        if (payload.runId == runId && payload.metadata['terminal'] == true) {
          failureSignals++;
        }
      });
      addTearDown(signal.cancel);
      await fixture.broker.publish(envelope);
      final running = fixture.drain(runtime);
      await store.entered.future.timeout(const Duration(seconds: 2));
      final status = (await fixture.backend.get(envelope.id))!;
      final recovered = TaskStatus.fromJson(
        (jsonDecode(jsonEncode(status.toJson())) as Map)
            .cast<String, Object?>(),
      );
      final marker = recovered.meta['stem.terminalFailureEnvelope']! as Map;
      final context = marker['context']! as Map;
      final firstToken = context['workflowExecutionId']! as String;
      expect(context['runId'], runId);
      expect(context['workflow'], 'fails');
      expect((await store.get(runId))!.executionId, firstToken);
      expect((await store.get(runId))!.ownerId, isNull);

      final newer = (await store.claimRunExecution(
        runId,
        ownerId: 'same-owner',
      ))!;
      expect(newer.executionId, isNot(firstToken));
      await store.markCompleted(runId, 'newer success');
      store.release.complete();
      await running;
      expect((await store.get(runId))!.result, 'newer success');
      expect(failureSignals, 0);

      // A reconstructed runtime must use the persisted old token, not inspect
      // the store for whichever execution identity happens to be current now.
      final restarted = fixture.runtime('reconstructed');
      await (restarted.workflowRunnerHandler() as TaskTerminalFailureHandler)
          .onTerminalFailure(envelope, recovered);
      expect(store.terminalTokens, [firstToken, firstToken]);
      expect((await store.get(runId))!.status, WorkflowStatus.completed);
      expect(failureSignals, 0);
    },
  );

  test(
    'same-execution failed notification can be retried after terminal write',
    () async {
      final store = InMemoryWorkflowStore();
      final fixture = _Fixture(store);
      addTearDown(fixture.close);
      StemSignals.configure(
        onError: (name, error, stack) =>
            Error.throwWithStackTrace(error, stack),
      );
      addTearDown(StemSignals.configure);
      final runtime = fixture.runtime('owner');
      final runId = await store.createRun(workflow: 'fails', params: const {});
      final envelope = Envelope(
        name: workflowRunTaskName,
        queue: runtime.queue,
        args: {'runId': runId},
      );
      var notifications = 0;
      final signal = StemSignals.workflowRunFailed.connect((payload, _) {
        if (payload.runId == runId &&
            payload.metadata['terminal'] == true &&
            ++notifications == 1) {
          throw StateError('notification unavailable');
        }
      });
      addTearDown(signal.cancel);
      await fixture.broker.publish(envelope);
      final outcome = await fixture.drain(runtime);
      expect(outcome.reason, WorkerRunStopReason.failed);
      expect((await store.get(runId))!.status, WorkflowStatus.failed);
      expect(notifications, 1);
      final failedMetrics = _workflowFailures();

      final status = (await fixture.backend.get(envelope.id))!;
      final recovered = TaskStatus.fromJson(
        (jsonDecode(jsonEncode(status.toJson())) as Map)
            .cast<String, Object?>(),
      );
      final restarted = fixture.runtime('reconstructed');
      await (restarted.workflowRunnerHandler() as TaskTerminalFailureHandler)
          .onTerminalFailure(envelope, recovered);
      expect(notifications, 2);
      expect(_workflowFailures(), failedMetrics);
      expect((await store.get(runId))!.status, WorkflowStatus.failed);
    },
  );

  test(
    'stale attempt failure does not emit execution-owned failure effects',
    () async {
      final store = _GatedFailureStore()..gateAttempt = true;
      final fixture = _Fixture(store);
      addTearDown(fixture.close);
      addTearDown(() {
        if (!store.releaseAttempt.isCompleted) store.releaseAttempt.complete();
      });
      final introspection = _RecordingIntrospection();
      final runtime = fixture.runtime(
        'attempt-owner',
        introspectionSink: introspection,
      );
      final runId = await store.createRun(workflow: 'fails', params: const {});
      var failureSignals = 0;
      final signal = StemSignals.workflowRunFailed.connect((payload, _) {
        if (payload.runId == runId) failureSignals++;
      });
      addTearDown(signal.cancel);
      final failedMetrics = _workflowFailures();

      final running = runtime.executeRun(runId);
      await store.attemptEntered.future.timeout(const Duration(seconds: 2));
      final oldToken = store.attemptToken!;
      await store.releaseRunExecution(runId, executionId: oldToken);
      await store.claimRunExecution(
        runId,
        ownerId: 'replacement',
      );
      await store.markCompleted(runId, 'replacement success');
      store.releaseAttempt.complete();

      await expectLater(running, throwsStateError);
      expect((await store.get(runId))!.result, 'replacement success');
      expect(store.attemptResult, TerminalFailureResult.superseded);
      expect(failureSignals, 0);
      expect(_workflowFailures(), failedMetrics);
      expect(
        introspection.events.where(
          (event) => event.type == WorkflowStepEventType.failed,
        ),
        isEmpty,
      );
    },
  );

  test(
    'stale context.step failure does not emit failed step introspection',
    () async {
      final store = _GatedFailureStore();
      final fixture = _Fixture(store);
      addTearDown(fixture.close);
      final entered = Completer<void>();
      final release = Completer<void>();
      final introspection = _RecordingIntrospection();
      final runtime = fixture.runtime(
        'step-owner',
        introspectionSink: introspection,
        definition: WorkflowScript<void>(
          name: 'step-fails',
          run: (script) => script.step<void>('actual-step', (context) async {
            entered.complete();
            await release.future;
            throw StateError('stale step failure');
          }),
        ).definition,
      );
      final runId = await store.createRun(
        workflow: 'step-fails',
        params: const {},
      );
      final running = runtime.executeRun(runId);
      await entered.future.timeout(const Duration(seconds: 2));
      final oldToken = (await store.get(runId))!.executionId!;
      await store.releaseRunExecution(runId, executionId: oldToken);
      await store.claimRunExecution(runId, ownerId: 'replacement');
      await store.markCompleted(runId, 'replacement success');
      release.complete();

      await expectLater(running, throwsStateError);
      expect((await store.get(runId))!.result, 'replacement success');
      expect(
        introspection.events.where(
          (event) => event.type == WorkflowStepEventType.failed,
        ),
        isEmpty,
      );
    },
  );

  test(
    'unknown workflow terminal notification recovers on managed redelivery',
    () async {
      final store = InMemoryWorkflowStore();
      final fixture = _Fixture(store);
      addTearDown(fixture.close);
      var notifications = 0;
      StemSignals.configure(
        onError: (name, error, stack) =>
            Error.throwWithStackTrace(error, stack),
      );
      addTearDown(StemSignals.configure);
      final runtime = fixture.runtime('unknown-owner');
      final runId = await store.createRun(
        workflow: 'missing.workflow',
        params: const {},
      );
      final envelope = Envelope(
        name: workflowRunTaskName,
        queue: runtime.queue,
        args: {'runId': runId},
      );
      final signal = StemSignals.workflowRunFailed.connect((payload, _) {
        if (payload.runId == runId && payload.metadata['terminal'] == true) {
          notifications++;
          if (notifications == 1) throw StateError('notification unavailable');
        }
      });
      addTearDown(signal.cancel);

      await fixture.broker.publish(envelope);
      final first = await fixture.drain(runtime);
      expect(first.reason, WorkerRunStopReason.failed);
      expect((await store.get(runId))!.status, WorkflowStatus.failed);
      expect(notifications, 1);
      final failedMetrics = _workflowFailures();

      // The first terminal callback failed after the fenced transition. A
      // transport redelivery must retry the callback, not rerun the handler.
      await fixture.broker.publish(envelope);
      await fixture.drain(runtime);
      expect(notifications, 2);
      expect(_workflowFailures(), failedMetrics);
      expect((await store.get(runId))!.status, WorkflowStatus.failed);
    },
  );

  test('unknown workflow releases its claim before a retry', () async {
    final store = InMemoryWorkflowStore();
    final fixture = _Fixture(store);
    addTearDown(fixture.close);
    final runtime = fixture.runtime('owner');
    final runId = await store.createRun(
      workflow: 'missing.workflow',
      params: const {},
    );
    String? previousToken;
    for (var attempt = 0; attempt < 2; attempt++) {
      final context = TaskContext(
        id: 'unknown-task',
        attempt: attempt,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );
      await expectLater(
        runtime.executeRun(runId, taskContext: context),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Unknown workflow'),
          ),
        ),
      );
      final state = (await store.get(runId))!;
      final token = context.terminalFailureContext['workflowExecutionId'];
      expect(token, isA<String>());
      expect(token, isNot(previousToken));
      expect(state.executionId, token);
      expect(state.ownerId, isNull);
      expect(state.leaseExpiresAt, isNull);
      expect(state.status, WorkflowStatus.running);
      previousToken = token! as String;
    }
  });

  test(
    'claim and run identity survive serialization without permissive defaults',
    () async {
      final store = InMemoryWorkflowStore();
      final id = await store.createRun(workflow: 'wire', params: const {});
      final claim = (await store.claimRunExecution(id, ownerId: 'owner'))!;
      expect(
        WorkflowExecutionClaim.fromJson(
          (jsonDecode(jsonEncode(claim.toJson())) as Map)
              .cast<String, Object?>(),
        ).toJson(),
        claim.toJson(),
      );
      final state = (await store.get(id))!;
      final decoded = RunState.fromJson(
        (jsonDecode(jsonEncode(state.toJson())) as Map).cast<String, Object?>(),
      );
      expect(decoded.executionId, claim.executionId);
      expect(decoded.copyWith(executionId: null).executionId, isNull);
      expect(
        () => WorkflowExecutionClaim.fromJson(const {}),
        throwsFormatException,
      );
    },
  );
}

int _workflowFailures() {
  final counters = StemMetrics.instance.snapshot()['counters']! as List;
  return counters
      .cast<Map<String, Object?>>()
      .where((row) {
        return row['name'] == 'stem.workflows.failed';
      })
      .fold<int>(0, (sum, row) => sum + (row['value']! as int));
}

class _Fixture {
  _Fixture(this.store);

  final InMemoryWorkflowStore store;
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final runtimes = <WorkflowRuntime>[];

  WorkflowRuntime runtime(
    String owner, {
    WorkflowIntrospectionSink? introspectionSink,
    WorkflowDefinition? definition,
  }) {
    final runtime =
        WorkflowRuntime(
          stem: Stem(
            broker: broker,
            backend: backend,
            registry: InMemoryTaskRegistry(),
          ),
          store: store,
          eventBus: InMemoryEventBus(store),
          runtimeId: owner,
          introspectionSink: introspectionSink,
        )..registerWorkflow(
          definition ??
              WorkflowScript<void>(
                name: 'fails',
                run: (_) async => throw StateError('execution failed'),
              ).definition,
        );
    runtimes.add(runtime);
    return runtime;
  }

  Future<WorkerRunOutcome> drain(WorkflowRuntime runtime) =>
      Worker(
        broker: broker,
        backend: backend,
        tasks: [runtime.workflowRunnerHandler()],
        queue: runtime.queue,
        concurrency: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      ).runUntilIdle(
        budget: const Duration(seconds: 3),
        shutdownReserve: Duration.zero,
        idleTimeout: const Duration(milliseconds: 100),
      );

  Future<void> close() async {
    for (final runtime in runtimes) {
      await runtime.dispose();
    }
    await broker.close();
    await backend.close();
  }
}

class _RecordingIntrospection implements WorkflowIntrospectionSink {
  final events = <WorkflowStepEvent>[];

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {
    events.add(event);
  }

  @override
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}

class _GatedFailureStore extends InMemoryWorkflowStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  final attemptEntered = Completer<void>();
  final releaseAttempt = Completer<void>();
  final terminalTokens = <String>[];
  String? attemptToken;
  TerminalFailureResult? attemptResult;
  bool gateAttempt = false;

  @override
  Future<TerminalFailureResult> markFailedForExecution(
    String runId, {
    required String executionId,
    required Object error,
    required StackTrace stack,
    bool terminal = true,
  }) async {
    if (terminal) {
      terminalTokens.add(executionId);
      if (!entered.isCompleted) entered.complete();
      await release.future;
    } else if (gateAttempt) {
      attemptToken = executionId;
      if (!attemptEntered.isCompleted) attemptEntered.complete();
      await releaseAttempt.future;
    }
    final result = await super.markFailedForExecution(
      runId,
      executionId: executionId,
      error: error,
      stack: stack,
      terminal: terminal,
    );
    if (!terminal) attemptResult = result;
    return result;
  }
}
