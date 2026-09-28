import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/workflow_store_contract_suite.dart';
import 'package:test/test.dart';

/// Verifies durable concurrency through public script and runtime APIs.
///
/// Stores must preserve independent waits and checkpoints across runtime
/// recreation, irrespective of event delivery and sibling completion order.
void runWorkflowConcurrencyContractTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow concurrency', () => _registerTests(factory));
}

void _registerTests(WorkflowStoreContractFactory factory) {
  late InMemoryBroker broker;
  WorkflowStore? createdStore;
  late WorkflowStore store;
  late FakeWorkflowClock clock;
  WorkflowRuntime? createdRuntime;
  late WorkflowRuntime runtime;

  WorkflowRuntime createRuntime() {
    final registry = InMemoryTaskRegistry();
    final result = WorkflowRuntime(
      stem: Stem(
        broker: broker,
        registry: registry,
        backend: InMemoryResultBackend(),
      ),
      store: store,
      eventBus: InMemoryEventBus(store),
      clock: clock,
    );
    registry.register(result.workflowRunnerHandler());
    createdRuntime = result;
    return result;
  }

  setUp(() async {
    broker = InMemoryBroker();
    clock = FakeWorkflowClock(DateTime.utc(2024));
    createdStore = await factory.create(clock);
    store = createdStore!;
    runtime = createRuntime();
  });

  tearDown(() async {
    await createdRuntime?.dispose();
    broker.dispose();
    if (createdStore != null) {
      await factory.dispose?.call(createdStore!);
    }
    createdStore = null;
    createdRuntime = null;
  });

  for (final reverseDelivery in [false, true]) {
    test('events survive restart, reverse=$reverseDelivery', () async {
      final completed = <String>[];
      final definition = WorkflowScript(
        name: 'parallel.events',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              final payload = await step.waitForEvent<Map<String, Object?>>(
                topic: 'event.$name',
              );
              completed.add(name);
              return payload['value'];
            }),
        ]),
      ).definition;
      runtime.registerWorkflow(definition);
      final id = await runtime.startWorkflow('parallel.events');
      await runtime.executeRun(id);
      expect((await store.get(id))!.status, WorkflowStatus.suspended);
      expect(await store.listWatchers('event.left'), hasLength(1));
      expect(await store.listWatchers('event.right'), hasLength(1));

      await runtime.dispose();
      runtime = createRuntime()..registerWorkflow(definition);
      final first = reverseDelivery ? 'right' : 'left';
      final second = reverseDelivery ? 'left' : 'right';
      await runtime.emit('event.$first', {'value': '$first-value'});
      await runtime.executeRun(id);
      expect(completed, [first]);
      expect(await store.readStep<String>(id, first), '$first-value');
      expect((await store.get(id))!.status, WorkflowStatus.suspended);
      expect(await store.listWatchers('event.$second'), hasLength(1));

      await runtime.dispose();
      runtime = createRuntime()..registerWorkflow(definition);
      await runtime.emit('event.$second', {'value': '$second-value'});
      await runtime.executeRun(id);
      expect(completed, [first, second]);
      final state = (await store.get(id))!;
      expect(state.status, WorkflowStatus.completed);
      expect(state.result, ['left-value', 'right-value']);
      expect(await store.listWatchers('event.left'), isEmpty);
      expect(await store.listWatchers('event.right'), isEmpty);
    });
  }

  test('event payloads survive delivery before execution', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.buffered-events',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              final payload = await step.waitForEvent<Map<String, Object?>>(
                topic: 'buffered.$name',
              );
              return payload['value'];
            }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.buffered-events');
    await runtime.executeRun(id);
    await runtime.emit('buffered.right', const {'value': 'right-value'});
    await runtime.emit('buffered.left', const {'value': 'left-value'});
    await runtime.executeRun(id);
    final state = (await store.get(id))!;
    expect(state.status, WorkflowStatus.completed);
    expect(state.result, ['left-value', 'right-value']);
  });

  test('a timer does not consume or replace a sibling event wait', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.mixed',
        run: (script) => Future.wait([
          script.step('timer', (step) async {
            await step.sleepFor(duration: const Duration(seconds: 2));
            return 'timer-value';
          }),
          script.step('event', (step) async {
            final payload = await step.waitForEvent<Map<String, Object?>>(
              topic: 'mixed.event',
            );
            return payload['value'];
          }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.mixed');
    await runtime.executeRun(id);
    clock.advance(const Duration(seconds: 2));
    expect(
      await runtime.resumeDueRuns(now: clock.now(), enqueue: false),
      contains(id),
    );
    await runtime.executeRun(id);
    expect(await store.readStep<String>(id, 'timer'), 'timer-value');
    expect((await store.get(id))!.status, WorkflowStatus.suspended);
    expect(await store.listWatchers('mixed.event'), hasLength(1));
    await runtime.emit('mixed.event', const {'value': 'event-value'});
    await runtime.executeRun(id);
    expect((await store.get(id))!.result, ['timer-value', 'event-value']);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
  });

  test('eager failure drains its sibling before releasing execution', () async {
    final siblingEntered = Completer<void>();
    final releaseSibling = Completer<void>();
    final scriptFailed = Completer<void>();
    final failure = StateError('failed branch');
    addTearDown(() {
      if (!releaseSibling.isCompleted) releaseSibling.complete();
    });
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.eager-error',
        run: (script) async {
          try {
            return await Future.wait([
              script.step('failure', (step) async {
                await siblingEntered.future;
                throw failure;
              }),
              script.step('sibling', (step) async {
                siblingEntered.complete();
                await releaseSibling.future;
                return 'sibling-value';
              }),
            ], eagerError: true);
          } on Object {
            scriptFailed.complete();
            rethrow;
          }
        },
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.eager-error');
    var executionEnded = false;
    final running = runtime.executeRun(id).whenComplete(() {
      executionEnded = true;
    });
    final failureExpectation = expectLater(running, throwsA(same(failure)));
    await scriptFailed.future;
    try {
      final active = (await store.get(id))!;
      expect(executionEnded, isFalse);
      expect(active.ownerId, isNotNull);
      expect(active.status, isNot(WorkflowStatus.completed));
    } finally {
      releaseSibling.complete();
      await failureExpectation;
    }
    expect((await store.get(id))!.ownerId, isNull);
  });

  test('invocation indices stay stable when cached steps replay', () async {
    final indices = <String, List<int>>{};
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.indices',
        run: (script) async {
          await script.step('seed', (step) async => 'seed-value');
          return Future.wait([
            for (final name in ['left', 'right'])
              script.step(name, (step) async {
                indices.putIfAbsent(name, () => []).add(step.stepIndex);
                final payload = await step.waitForEvent<Map<String, Object?>>(
                  topic: 'indices.$name',
                );
                return payload['value'];
              }),
          ]);
        },
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.indices');
    await runtime.executeRun(id);
    await runtime.emit('indices.left', const {'value': 'left-value'});
    await runtime.executeRun(id);
    await runtime.emit('indices.right', const {'value': 'right-value'});
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
    expect(indices['left'], everyElement(1));
    expect(indices['right'], everyElement(2));
  });

  test('named branches isolate duplicate local names across replay', () async {
    final invocations = <String>[];
    final branchPrevious = <Object?>[];
    final definition = WorkflowScript(
      name: 'parallel.scoped',
      run: (script) async {
        await script.step('seed', (step) async => 'seed-value');
        final joined = await script.parallel<String>({
          for (final name in ['left', 'right'])
            name: (branch) => branch.step('work', (step) async {
              branchPrevious.add(step.previousResult);
              invocations.add(name);
              return '$name-value';
            }),
        });
        await script.step('after-join', (step) async {
          return step.waitForEvent<Map<String, Object?>>(
            topic: 'scoped.finish',
          );
        });
        return joined;
      },
    ).definition;
    runtime.registerWorkflow(definition);
    final id = await runtime.startWorkflow('parallel.scoped');
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.suspended);
    expect(invocations, unorderedEquals(['left', 'right']));
    expect(branchPrevious, ['seed-value', 'seed-value']);
    await runtime.dispose();
    runtime = createRuntime()..registerWorkflow(definition);
    await runtime.emit('scoped.finish', const {'done': true});
    await runtime.executeRun(id);
    final state = (await store.get(id))!;
    expect(state.status, WorkflowStatus.completed);
    expect(state.result, {'left': 'left-value', 'right': 'right-value'});
    expect(invocations, hasLength(2));
  });

  test('parallel starts siblings after a synchronous branch error', () async {
    var siblingStarted = false;
    final failure = StateError('synchronous branch failure');
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.synchronous-error',
        run: (script) => script.parallel<String>({
          'failure': (_) => throw failure,
          'sibling': (branch) => branch.step('work', (step) async {
            siblingStarted = true;
            return 'sibling-value';
          }),
        }),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.synchronous-error');
    await expectLater(runtime.executeRun(id), throwsA(same(failure)));
    expect(siblingStarted, isTrue);
  });

  test('one event resolves both steps waiting on the same topic', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.shared-topic',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              final payload = await step.waitForEvent<Map<String, Object?>>(
                topic: 'shared-topic',
              );
              return '$name:${payload['value']}';
            }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.shared-topic');
    await runtime.executeRun(id);
    await runtime.emit('shared-topic', const {'value': 'delivered'});
    await runtime.executeRun(id);
    final state = (await store.get(id))!;
    expect(state.status, WorkflowStatus.completed);
    expect(state.result, ['left:delivered', 'right:delivered']);
    expect(await store.listWatchers('shared-topic'), isEmpty);
  });

  test('a null-valued concurrent checkpoint is not executed again', () async {
    var nullStepCalls = 0;
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.null',
        run: (script) => Future.wait<Object?>([
          script.step<Object?>('null-result', (step) async {
            nullStepCalls++;
            return null;
          }),
          script.step('event', (step) async {
            final payload = await step.waitForEvent<Map<String, Object?>>(
              topic: 'null.finish',
            );
            return payload['value'];
          }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.null');
    await runtime.executeRun(id);
    expect(nullStepCalls, 1);
    await runtime.emit('null.finish', const {'value': 'finished'});
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
    expect((await store.get(id))!.result, [null, 'finished']);
    expect(nullStepCalls, 1);
  });

  test('cancellation removes all outstanding branch watchers', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.cancel',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(
              name,
              (step) => step.waitForEvent<Map<String, Object?>>(
                topic: 'cancel.$name',
              ),
            ),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.cancel');
    await runtime.executeRun(id);
    await runtime.cancelWorkflow(id);
    expect((await store.get(id))!.status, WorkflowStatus.cancelled);
    expect(await store.listWatchers('cancel.left'), isEmpty);
    expect(await store.listWatchers('cancel.right'), isEmpty);
    await runtime.emit('cancel.left', const {'value': 'late-left'});
    await runtime.emit('cancel.right', const {'value': 'late-right'});
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.cancelled);
  });

  test('an event batch wakes every matching run, not just the first', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.multirun',
        run: (script) => script.step(
          'wait',
          (step) => step.waitForEvent<Map<String, Object?>>(topic: 'batch'),
        ),
      ).definition,
    );
    final ids = <String>[];
    for (var index = 0; index < 3; index++) {
      final id = await runtime.startWorkflow('parallel.multirun');
      ids.add(id);
      await runtime.executeRun(id);
    }
    await runtime.emit('batch', const {'delivered': true});
    for (final id in ids) {
      expect((await store.get(id))!.status, WorkflowStatus.running);
      await runtime.executeRun(id);
      expect((await store.get(id))!.status, WorkflowStatus.completed);
    }
  });

  test('direct sleeps resume without resetting their deadline', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.direct-sleep',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              await step.sleep(const Duration(seconds: 1));
              return name;
            }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.direct-sleep');
    await runtime.executeRun(id);
    clock.advance(const Duration(seconds: 1));
    await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
    expect((await store.get(id))!.result, ['left', 'right']);
  });

  test('parallel event deadlines resume with timeout metadata', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.deadlines',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              if ((step as WorkflowScriptResumeDetails).isEventTimeout) {
                return '$name-timeout';
              }
              await step.awaitEvent(
                'deadline.$name',
                deadline: clock.now().add(const Duration(seconds: 1)),
              );
              return 'waiting';
            }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.deadlines');
    await runtime.executeRun(id);
    clock.advance(const Duration(seconds: 1));
    await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
    expect((await store.get(id))!.result, ['left-timeout', 'right-timeout']);
  });

  test(
    'event limits count matching waits rather than unrelated rows',
    () async {
      runtime.registerWorkflow(
        WorkflowScript(
          name: 'parallel.filtered-events',
          run: (script) => script.step(
            'wait',
            (step) => step.waitForEvent<Map<String, Object?>>(
              topic: script.params['topic']! as String,
            ),
          ),
        ).definition,
      );
      final unrelated = await runtime.startWorkflow(
        'parallel.filtered-events',
        params: const {'topic': 'unrelated'},
      );
      await runtime.executeRun(unrelated);
      clock.advance(const Duration(milliseconds: 1));
      final target = await runtime.startWorkflow(
        'parallel.filtered-events',
        params: const {'topic': 'target'},
      );
      await runtime.executeRun(target);
      final resolved = await (store as WorkflowConcurrentStore)
          .resolveConcurrentEvents('target', const {'ready': true}, limit: 1);
      expect(resolved.map((record) => record.runId), [target]);
      expect((await store.get(unrelated))!.status, WorkflowStatus.suspended);
      await runtime.executeRun(target);
      expect((await store.get(target))!.status, WorkflowStatus.completed);
    },
  );

  test('timer limits count due waits rather than future deadlines', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.filtered-timers',
        run: (script) => script.step('wait', (step) async {
          await step.sleep(
            Duration(seconds: script.params['seconds']! as int),
          );
          return 'done';
        }),
      ).definition,
    );
    final later = await runtime.startWorkflow(
      'parallel.filtered-timers',
      params: const {'seconds': 10},
    );
    await runtime.executeRun(later);
    clock.advance(const Duration(milliseconds: 1));
    final earlier = await runtime.startWorkflow(
      'parallel.filtered-timers',
      params: const {'seconds': 1},
    );
    await runtime.executeRun(earlier);
    clock.advance(const Duration(seconds: 1));
    final due = await (store as WorkflowConcurrentStore)
        .resumeDueConcurrentSteps(clock.now(), limit: 1);
    expect(due.map((record) => record.runId), [earlier]);
    expect((await store.get(later))!.status, WorkflowStatus.suspended);
    await runtime.executeRun(earlier);
    expect((await store.get(earlier))!.status, WorkflowStatus.completed);
  });

  test('delivered payload survives a failed resumed handler', () async {
    var resumedAttempts = 0;
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.resume-retry',
        run: (script) => script.step('wait', (step) async {
          final payload = await step.waitForEvent<Map<String, Object?>>(
            topic: 'resume-retry',
          );
          if (++resumedAttempts == 1) throw StateError('retry after delivery');
          return payload['value'];
        }),
      ).definition,
    );
    final id = await runtime.startWorkflow('parallel.resume-retry');
    await runtime.executeRun(id);
    await runtime.emit('resume-retry', const {'value': 'durable-payload'});
    await expectLater(runtime.executeRun(id), throwsStateError);
    await runtime.executeRun(id);
    expect((await store.get(id))!.status, WorkflowStatus.completed);
    expect((await store.get(id))!.result, 'durable-payload');
    expect(resumedAttempts, 2);
  });

  test('concurrent timers respect the suspension duration policy', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'parallel.suspension-policy',
        run: (script) => Future.wait([
          for (final name in ['left', 'right'])
            script.step(name, (step) async {
              await step.sleep(const Duration(seconds: 10));
              return name;
            }),
        ]),
      ).definition,
    );
    final id = await runtime.startWorkflow(
      'parallel.suspension-policy',
      cancellationPolicy: const WorkflowCancellationPolicy(
        maxSuspendDuration: Duration(seconds: 1),
      ),
    );
    await runtime.executeRun(id);
    clock.advance(const Duration(seconds: 1));
    await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
    expect((await store.get(id))!.status, WorkflowStatus.cancelled);
  });

  test(
    'concurrent CAS rejects stale revisions and completed rewrites',
    () async {
      final id = await store.createRun(workflow: 'cas', params: const {});
      final claim = (await (store as FencedWorkflowStore).claimRunExecution(
        id,
        ownerId: 'cas-owner',
      ))!;
      final concurrent = store as WorkflowConcurrentStore;
      WorkflowConcurrentStepRecord record(int revision, {bool done = false}) =>
          WorkflowConcurrentStepRecord(
            runId: id,
            invocationId: 'logical-step',
            branch: '',
            stepName: 'step',
            stepIndex: 0,
            iteration: 0,
            revision: revision,
            status: done
                ? WorkflowConcurrentStepStatus.completed
                : WorkflowConcurrentStepStatus.running,
            executionId: claim.executionId,
            updatedAt: clock.now(),
            value: done ? 'done' : null,
          );
      await concurrent.writeConcurrentStep(
        record(1),
        executionId: claim.executionId,
      );
      await expectLater(
        concurrent.writeConcurrentStep(
          record(2, done: true),
          expectedRevision: 0,
          executionId: claim.executionId,
          checkpointName: 'rejected',
        ),
        throwsStateError,
      );
      await expectLater(
        concurrent.writeConcurrentStep(
          record(3),
          expectedRevision: 1,
          executionId: claim.executionId,
        ),
        throwsStateError,
      );
      expect(
        (await concurrent.readConcurrentStep(id, 'logical-step'))!.revision,
        1,
      );
      expect(await store.readStep<String>(id, 'rejected'), isNull);
      await concurrent.writeConcurrentStep(
        record(2, done: true),
        expectedRevision: 1,
        executionId: claim.executionId,
        checkpointName: 'projected',
      );
      expect(await store.readStep<String>(id, 'projected'), 'done');
      await expectLater(
        concurrent.writeConcurrentStep(
          record(3, done: true),
          expectedRevision: 2,
          executionId: claim.executionId,
          checkpointName: 'rejected-rewrite',
        ),
        throwsStateError,
      );
      expect(
        (await concurrent.readConcurrentStep(id, 'logical-step'))!.revision,
        2,
      );
      expect(await store.readStep<String>(id, 'rejected-rewrite'), isNull);
    },
  );
}
