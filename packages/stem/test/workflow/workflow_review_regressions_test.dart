import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late FakeWorkflowClock clock;
  late InMemoryWorkflowStore store;
  late _FailOnceBroker broker;
  late InMemoryResultBackend backend;
  late WorkflowRuntime runtime;

  WorkflowRuntime createRuntime({
    WorkflowStore? storage,
    WorkflowIntrospectionSink? introspection,
  }) {
    final registry = InMemoryTaskRegistry();
    final result = WorkflowRuntime(
      stem: Stem(broker: broker, registry: registry, backend: backend),
      store: storage ?? store,
      eventBus: InMemoryEventBus(storage ?? store),
      clock: clock,
      introspectionSink: introspection,
    );
    addTearDown(result.dispose);
    registry.register(result.workflowRunnerHandler());
    return result;
  }

  setUp(() {
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = InMemoryWorkflowStore(clock: clock);
    broker = _FailOnceBroker();
    addTearDown(broker.dispose);
    backend = InMemoryResultBackend();
    addTearDown(backend.close);
    runtime = createRuntime();
  });

  test('publish failure does not skip concurrent or legacy due runs', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'review.due',
        run: (script) => script.step('wait', (step) async {
          await step.sleep(const Duration(seconds: 1));
          return 'done';
        }),
      ).definition,
    );
    final first = await runtime.startWorkflow('review.due');
    await runtime.executeRun(first);
    final second = await runtime.startWorkflow('review.due');
    await runtime.executeRun(second);
    final legacy = await store.createRun(workflow: 'review.due', params: {});
    await store.suspendUntil(
      legacy,
      'wait',
      clock.now().add(const Duration(seconds: 1)),
    );
    clock.advance(const Duration(seconds: 1));
    final failure = StateError('first continuation publish failed');
    broker
      ..attemptedRuns.clear()
      ..nextFailure = failure;

    await expectLater(
      runtime.resumeDueRuns(now: clock.now()),
      throwsA(same(failure)),
    );
    expect(broker.attemptedRuns, [first, second, legacy]);
  });

  test(
    'legacy stores support sequential and cached steps of each kind',
    () async {
      await runtime.dispose();
      runtime = createRuntime(storage: _LegacyStore(store));
      final called = <String>[];
      runtime.registerWorkflow(
        WorkflowScript(
          name: 'review.legacy',
          run: (script) async {
            await script.step('a', (_) {
              called.add('a');
              return 'a';
            });
            await script.step<void>('b', (_) => called.add('b'));
            await script.step<void>('c', (_) async => called.add('c'));
            return script.step<String>(
              'a',
              (_) => throw StateError('completed handler must not run again'),
            );
          },
        ).definition,
      );
      final id = await runtime.startWorkflow('review.legacy');
      await runtime.executeRun(id);
      expect(called, ['a', 'b', 'c']);
      expect((await store.get(id))!.status, WorkflowStatus.completed);
      expect((await store.get(id))!.result, 'a');
    },
  );

  test('legacy stores still reject genuinely overlapping steps', () async {
    await runtime.dispose();
    runtime = createRuntime(storage: _LegacyStore(store));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'review.legacy-overlap',
        run: (script) async {
          final first = script.step('a', (_) => release.future);
          try {
            await expectLater(
              script.step('b', (_) => 'b'),
              throwsUnsupportedError,
            );
          } finally {
            release.complete();
          }
          await first;
          return 'done';
        },
      ).definition,
    );
    final id = await runtime.startWorkflow('review.legacy-overlap');
    await runtime.executeRun(id);
    expect((await store.get(id))!.result, 'done');
  });

  test(
    'same-named branches have distinct lifecycle event identities',
    () async {
      await runtime.dispose();
      final sink = _RecordingIntrospection();
      runtime = createRuntime(introspection: sink)
        ..registerWorkflow(
          WorkflowScript(
            name: 'review.metrics',
            run: (script) => script.parallel<String>({
              'left': (branch) => branch.step('load', (_) => 'left'),
              'right': (branch) => branch.step('load', (_) => 'right'),
            }),
          ).definition,
        );
      final id = await runtime.startWorkflow('review.metrics');
      await runtime.executeRun(id);
      final started = sink.steps
          .where((step) => step.type == WorkflowStepEventType.started)
          .map((step) => step.metadata?['invocationId'])
          .toList();
      final completed = sink.steps
          .where((step) => step.type == WorkflowStepEventType.completed)
          .map((step) => step.metadata?['invocationId'])
          .toList();
      expect(started, hasLength(2));
      expect(started, everyElement(isA<String>()));
      expect(started.toSet(), hasLength(2));
      expect(completed, unorderedEquals(started));
    },
  );
}

class _FailOnceBroker extends InMemoryBroker {
  StateError? nextFailure;
  final attemptedRuns = <String>[];

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    attemptedRuns.add(envelope.args['runId']! as String);
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    await super.publish(envelope, routing: routing);
  }
}

class _RecordingIntrospection implements WorkflowIntrospectionSink {
  final steps = <WorkflowStepEvent>[];

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async =>
      steps.add(event);

  @override
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}

/// Deliberately exposes only the original store contract, not capabilities.
class _LegacyStore implements WorkflowStore {
  _LegacyStore(this.delegate);

  final InMemoryWorkflowStore delegate;

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? runId,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) => delegate.createRun(
    workflow: workflow,
    params: params,
    runId: runId,
    parentRunId: parentRunId,
    ttl: ttl,
    cancellationPolicy: cancellationPolicy,
  );

  @override
  Future<RunState?> get(String runId) => delegate.get(runId);

  @override
  Future<T?> readStep<T>(String runId, String stepName) =>
      delegate.readStep<T>(runId, stepName);

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) =>
      delegate.saveStep(runId, stepName, value);

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) =>
      delegate.listSteps(runId);

  @override
  Future<void> markRunning(String runId, {String? stepName}) =>
      delegate.markRunning(runId, stepName: stepName);

  @override
  Future<void> markCompleted(String runId, Object? result) =>
      delegate.markCompleted(runId, result);

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) => delegate.markFailed(runId, error, stack, terminal: terminal);

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) => delegate.claimRun(
    runId,
    ownerId: ownerId,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) => delegate.renewRunLease(
    runId,
    ownerId: ownerId,
    leaseDuration: leaseDuration,
  );

  @override
  Future<void> releaseRun(String runId, {required String ownerId}) =>
      delegate.releaseRun(runId, ownerId: ownerId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected legacy-store call: $invocation');
}
