import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

/// Regression tests for shared execution state observed in Stem 0.5.1.
void main() {
  late InMemoryBroker broker;
  late InMemoryWorkflowStore store;
  late WorkflowRuntime runtime;
  late FakeWorkflowClock clock;

  setUp(() {
    broker = InMemoryBroker();
    final registry = InMemoryTaskRegistry();
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = InMemoryWorkflowStore(clock: clock);
    runtime = WorkflowRuntime(
      stem: Stem(
        broker: broker,
        registry: registry,
        backend: InMemoryResultBackend(),
      ),
      store: store,
      eventBus: InMemoryEventBus(store),
      clock: clock,
    );
    registry.register(runtime.workflowRunnerHandler());
  });

  tearDown(() async {
    await runtime.dispose();
    broker.dispose();
  });

  test(
    'overlapping steps have distinct indices and stable snapshots',
    () async {
      final secondEntered = Completer<void>();
      final firstCompleted = Completer<void>();
      final indices = <int>[];
      final previous = <Object?>[];
      runtime.registerWorkflow(
        WorkflowScript(
          name: 'concurrent.bookkeeping',
          run: (script) async {
            final first = script.step('first', (step) async {
              indices.add(step.stepIndex);
              await secondEntered.future;
              return 'first-value';
            });
            final second = script.step('second', (step) async {
              indices.add(step.stepIndex);
              previous.add(step.previousResult);
              secondEntered.complete();
              await firstCompleted.future;
              previous.add(step.previousResult);
              return 'second-value';
            });
            await first;
            firstCompleted.complete();
            return Future.wait([first, second]);
          },
        ).definition,
      );

      final id = await runtime.startWorkflow('concurrent.bookkeeping');
      await runtime.executeRun(id);
      expect((await store.get(id))?.status, WorkflowStatus.completed);
      expect(indices, [0, 1]);
      expect(previous, [null, null]);
      // Distinct checkpoint names do preserve the individual results.
      expect(await store.readStep<String>(id, 'first'), 'first-value');
      expect(await store.readStep<String>(id, 'second'), 'second-value');
    },
  );

  test('overlapping sleeps preserve independent deadlines on replay', () async {
    final attempts = <String, int>{};
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'concurrent.sleep',
        run: (script) async {
          final earlySuspended = Completer<void>();
          final early = script.step('early', (step) async {
            attempts.update('early', (value) => value + 1, ifAbsent: () => 1);
            if (step.takeResumeData() != true) {
              await step.sleep(const Duration(seconds: 1));
            }
            return 'early-value';
          });
          // Observe completion without swallowing the suspension from wait.
          final observedEarly = early.whenComplete(earlySuspended.complete);
          final late = script.step('late', (step) async {
            attempts.update('late', (value) => value + 1, ifAbsent: () => 1);
            await earlySuspended.future;
            if (step.takeResumeData() != true) {
              await step.sleep(const Duration(seconds: 10));
            }
            return 'late-value';
          });
          return Future.wait([observedEarly, late]);
        },
      ).definition,
    );

    final id = await runtime.startWorkflow('concurrent.sleep');
    await runtime.executeRun(id);
    final suspended = (await store.get(id))!;
    expect(suspended.status, WorkflowStatus.suspended);
    expect(suspended.suspensionStep, 'early');
    expect(suspended.resumeAt, clock.now().add(const Duration(seconds: 1)));
    clock.advance(const Duration(seconds: 1));
    expect(await store.dueRuns(clock.now()), contains(id));

    await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
    await runtime.executeRun(id);
    final replayed = (await store.get(id))!;
    expect(attempts, {'early': 2, 'late': 1});
    expect(replayed.status, WorkflowStatus.suspended);
    expect(replayed.suspensionStep, 'late');
    expect(replayed.resumeAt, clock.now().add(const Duration(seconds: 9)));
    expect(await store.readStep<String>(id, 'early'), 'early-value');
    expect(await store.readStep<String>(id, 'late'), isNull);

    clock.advance(const Duration(seconds: 9));
    await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
    await runtime.executeRun(id);
    expect((await store.get(id))?.status, WorkflowStatus.completed);
    expect(attempts, {'early': 2, 'late': 2});
  });
}
