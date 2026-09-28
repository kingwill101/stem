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
  late WorkflowStore store;
  late FakeWorkflowClock clock;
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
    addTearDown(result.dispose);
    registry.register(result.workflowRunnerHandler());
    return result;
  }

  setUp(() async {
    broker = InMemoryBroker();
    addTearDown(broker.dispose);
    clock = FakeWorkflowClock(DateTime.utc(2024));
    final createdStore = await factory.create(clock);
    addTearDown(() async => factory.dispose?.call(createdStore));
    store = createdStore;
    runtime = createRuntime();
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

  test(
    'branch idempotency keys are isolated and stable across replay',
    () async {
      final keys = <String, String>{};
      final definition = WorkflowScript(
        name: 'parallel.idempotency',
        run: (script) async {
          await script.step('load', (step) {
            keys['root'] = step.idempotencyKey();
            return 'root';
          });
          final result = await script.parallel<String>({
            for (final name in ['customer', 'inventory'])
              name: (branch) => branch.step('load', (step) {
                keys[name] = step.idempotencyKey();
                keys['$name-custom'] = step.idempotencyKey('custom');
                return keys[name]!;
              }),
          });
          await script.step(
            'gate',
            (step) => step.waitForEvent<Map<String, Object?>>(
              topic: 'idempotency.continue',
            ),
          );
          return result;
        },
      ).definition;
      runtime.registerWorkflow(definition);
      final id = await runtime.startWorkflow('parallel.idempotency');
      await runtime.executeRun(id);
      expect(keys['root'], 'parallel.idempotency/$id/load');
      expect(keys.values.toSet(), hasLength(5));
      final beforeReplay = Map<String, String>.of(keys);
      await runtime.dispose();
      runtime = createRuntime()..registerWorkflow(definition);
      await runtime.emit('idempotency.continue', const {'ready': true});
      await runtime.executeRun(id);
      expect((await store.get(id))!.status, WorkflowStatus.completed);
      expect((await store.get(id))!.result, {
        'customer': beforeReplay['customer'],
        'inventory': beforeReplay['inventory'],
      });
      expect(keys, beforeReplay);
    },
  );

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

  test(
    'mixed watcher batches return every transition within the limit',
    () async {
      final legacy = await store.createRun(workflow: 'mixed', params: {});
      await store.registerWatcher(legacy, 'legacy', 'mixed.batch');
      runtime.registerWorkflow(
        WorkflowScript(
          name: 'mixed.concurrent',
          run: (script) => script.step(
            'wait',
            (step) => step.waitForEvent<Map<String, Object?>>(
              topic: 'mixed.batch',
            ),
          ),
        ).definition,
      );
      final current = await runtime.startWorkflow('mixed.concurrent');
      await runtime.executeRun(current);
      final first = await store.resolveWatchers(
        'mixed.batch',
        const {'value': 1},
        limit: 1,
      );
      expect(first, hasLength(1));
      expect(await store.listWatchers('mixed.batch'), hasLength(1));
      final second = await store.resolveWatchers(
        'mixed.batch',
        const {'value': 2},
        limit: 1,
      );
      expect(second, hasLength(1));
      expect(
        [...first, ...second].map((item) => item.runId),
        unorderedEquals([legacy, current]),
      );
      expect(await store.listWatchers('mixed.batch'), isEmpty);
    },
  );

  test('waiting-run lookup filters topics before limiting children', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'lookup.concurrent',
        run: (script) => Future.wait([
          script.step(
            'other',
            (step) => step.waitForEvent<Map<String, Object?>>(
              topic: 'lookup.other',
            ),
          ),
          if (script.params['target'] == true)
            script.step(
              'target',
              (step) => step.waitForEvent<Map<String, Object?>>(
                topic: 'lookup.target',
              ),
            ),
        ]),
      ).definition,
    );
    final unrelated = await runtime.startWorkflow('lookup.concurrent');
    await runtime.executeRun(unrelated);
    clock.advance(const Duration(milliseconds: 1));
    final target = await runtime.startWorkflow(
      'lookup.concurrent',
      params: const {'target': true},
    );
    await runtime.executeRun(target);
    expect(
      await store.runsWaitingOn('lookup.target', limit: 1),
      [target],
    );
  });

  test('concurrent watcher inspection preserves the deadline', () async {
    final deadline = clock.now().add(const Duration(minutes: 1));
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'watcher.deadline',
        run: (script) => script.step(
          'wait',
          (step) => step.waitForEvent<Map<String, Object?>>(
            topic: 'watcher.deadline',
            deadline: deadline,
          ),
        ),
      ).definition,
    );
    final id = await runtime.startWorkflow('watcher.deadline');
    await runtime.executeRun(id);
    final watcher = (await store.listWatchers('watcher.deadline')).single;
    expect(watcher.runId, id);
    expect(watcher.deadline, deadline);
  });

  for (final mode in ['event', 'timer', 'manual']) {
    test('opaque JSON survives $mode resolution and readback', () async {
      // VM stores must preserve integers outside JavaScript's exact range.
      // ignore: avoid_js_rounded_ints
      const largeInteger = 9007199254740993;
      const opaque = <String, Object?>{
        'emptyList': <Object?>[],
        'emptyMap': <String, Object?>{},
        'largeInteger': largeInteger,
        'nullable': null,
        'nested': <Object?>[
          <Object?>[],
          <String, Object?>{'items': <Object?>[], 'large': largeInteger},
        ],
      };
      final id = await store.createRun(workflow: 'opaque', params: {});
      final claim = (await (store as FencedWorkflowStore).claimRunExecution(
        id,
        ownerId: 'opaque-owner',
      ))!;
      final concurrent = store as WorkflowConcurrentStore;
      final data = <String, Object?>{
        'type': mode == 'event' ? 'event' : 'sleep',
        if (mode == 'event') 'topic': 'opaque.event',
        if (mode != 'event')
          'resumeAt': clock
              .now()
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        'custom': opaque,
        'payloadRaw': 'user-owned metadata, not a wire encoding',
        if (mode != 'event') 'payload': opaque,
      };
      await concurrent.writeConcurrentStep(
        WorkflowConcurrentStepRecord(
          runId: id,
          invocationId: 'opaque-step',
          branch: '',
          stepName: 'wait',
          stepIndex: 0,
          iteration: 0,
          revision: 1,
          status: WorkflowConcurrentStepStatus.suspended,
          executionId: claim.executionId,
          value: opaque,
          suspensionData: data,
          updatedAt: clock.now(),
        ),
        executionId: claim.executionId,
      );
      await (store as FencedWorkflowStore).releaseRunExecution(
        id,
        executionId: claim.executionId,
      );
      if (mode == 'event') {
        await concurrent.resolveConcurrentEvents('opaque.event', opaque);
      } else {
        clock.advance(const Duration(seconds: 1));
        if (mode == 'timer') {
          await concurrent.resumeDueConcurrentSteps(clock.now());
        } else {
          final state = (await store.get(id))!;
          await store.markResumed(id, data: state.suspensionData);
        }
      }
      final record = (await concurrent.readConcurrentStep(id, 'opaque-step'))!;
      expect(record.status, WorkflowConcurrentStepStatus.ready);
      expect(record.value, opaque);
      expect(record.suspensionData?['custom'], opaque);
      expect(record.suspensionData?['payload'], opaque);
      expect(
        record.suspensionData?['payloadRaw'],
        'user-owned metadata, not a wire encoding',
      );
      final payload = record.suspensionData!['payload']! as Map;
      expect(payload['largeInteger'], isA<int>());
    });
  }

  test('execution outcome settlement fences stale and terminal runs', () async {
    final id = await store.createRun(workflow: 'settlement.fence', params: {});
    final fenced = store as FencedWorkflowStore;
    final concurrent = store as WorkflowConcurrentStore;
    final first = (await fenced.claimRunExecution(id, ownerId: 'first'))!;
    await concurrent.releaseConcurrentExecution(
      id,
      executionId: first.executionId,
      suspended: false,
    );
    final second = (await fenced.claimRunExecution(id, ownerId: 'second'))!;
    await concurrent.releaseConcurrentExecution(
      id,
      executionId: first.executionId,
      suspended: true,
    );
    expect((await store.get(id))!.ownerId, 'second');
    expect((await store.get(id))!.executionId, second.executionId);
    await store.cancel(id);
    await concurrent.releaseConcurrentExecution(
      id,
      executionId: second.executionId,
      suspended: false,
    );
    expect((await store.get(id))!.status, WorkflowStatus.cancelled);
  });

  for (final handling in ['try/catch', 'catchError', 'parallel']) {
    test('handled failure suspends and resumes with $handling', () async {
      Future<String> body(WorkflowScriptContext script) async {
        final failed = script.step<String>(
          'handled',
          (_) => throw const FormatException('handled by application'),
        );
        if (handling == 'catchError') {
          await failed.catchError((Object _) => 'fallback');
        } else {
          try {
            await failed;
          } on FormatException {
            // This is an application-handled action failure, not a run failure.
          }
        }
        await script.step('wait', (step) async {
          await step.sleep(const Duration(seconds: 1));
          return 'slept';
        });
        return 'done';
      }

      runtime.registerWorkflow(
        WorkflowScript<Object?>(
          name: 'handled.failure',
          run: (script) => handling == 'parallel'
              ? script.parallel<String>({'branch': body})
              : body(script),
        ).definition,
      );
      final id = await runtime.startWorkflow('handled.failure');
      await runtime.executeRun(id);
      expect((await store.get(id))!.status, WorkflowStatus.suspended);
      expect(
        await (store as WorkflowConcurrentStore).listConcurrentSteps(id),
        contains(
          isA<WorkflowConcurrentStepRecord>().having(
            (record) => record.status,
            'retained failed checkpoint',
            WorkflowConcurrentStepStatus.failed,
          ),
        ),
      );
      clock.advance(const Duration(seconds: 1));
      await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
      await runtime.executeRun(id);
      expect((await store.get(id))!.status, WorkflowStatus.completed);
      expect(
        (await store.get(id))!.result,
        handling == 'parallel' ? {'branch': 'done'} : 'done',
      );
    });
  }

  for (final structured in [false, true]) {
    test('join outcome policy: parallel=$structured', () async {
      final failure = StateError('uncaught branch failure');
      runtime.registerWorkflow(
        WorkflowScript<Object?>(
          name: 'join.outcomes',
          run: (script) {
            final suspended = Completer<void>();
            Future<String> wait(WorkflowScriptContext branch) => branch
                .step('wait', (step) async {
                  await step.sleep(const Duration(seconds: 1));
                  return 'slept';
                })
                .whenComplete(suspended.complete);
            Future<String> fail(WorkflowScriptContext branch) =>
                branch.step('fail', (_) async {
                  await suspended.future;
                  throw failure;
                });
            if (structured) {
              return script.parallel<String>({'wait': wait, 'fail': fail});
            }
            return Future.wait([wait(script), fail(script)]);
          },
        ).definition,
      );
      final id = await runtime.startWorkflow('join.outcomes');
      if (structured) {
        await expectLater(runtime.executeRun(id), throwsA(same(failure)));
        expect((await store.get(id))!.status, WorkflowStatus.running);
      } else {
        // Ordinary Future.wait exposes its first error, here a suspension.
        await runtime.executeRun(id);
        expect((await store.get(id))!.status, WorkflowStatus.suspended);
        clock.advance(const Duration(seconds: 1));
        await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
        // On replay the wait succeeds, so the unhandled action failure escapes.
        await expectLater(runtime.executeRun(id), throwsA(same(failure)));
        expect((await store.get(id))!.status, WorkflowStatus.running);
      }
    });
  }

  test('escaping script errors remain retryable after a wait', () async {
    final failure = StateError('failure outside a checkpoint');
    runtime.registerWorkflow(
      WorkflowScript<Object?>(
        name: 'script.failure',
        run: (script) async {
          try {
            await script.step('wait', (step) async {
              await step.sleep(const Duration(seconds: 1));
            });
          } on Object {
            throw failure;
          }
          return 'done';
        },
      ).definition,
    );
    final id = await runtime.startWorkflow('script.failure');
    await expectLater(runtime.executeRun(id), throwsA(same(failure)));
    final state = (await store.get(id))!;
    expect(state.status, WorkflowStatus.running);
    expect(state.ownerId, isNull);
    expect(state.waitTopic, isNull);
    expect(await store.listRunnableRuns(now: clock.now()), contains(id));
  });

  for (final script in [false, true]) {
    for (final event in [false, true]) {
      test(
        'runtime owns suspension routing: script=$script event=$event',
        () async {
          const data = <String, Object?>{
            'step': 'wrong-step',
            'iterationStep': 'wrong-step',
            'iteration': 99,
            'type': 'wrong-type',
            'topic': 'wrong-topic',
            'dueAt': '1900-01-01T00:00:00.000Z',
            'resumeAt': '1900-01-01T00:00:00.000Z',
            'deadline': '1900-01-01T00:00:00.000Z',
            'suspendedAt': '1900-01-01T00:00:00.000Z',
            'policyDeadline': '1900-01-01T00:00:00.000Z',
            'policyDeadlineApplied': true,
            'resumeReason': 'eventDeadline',
            'deliveredAt': '1900-01-01T00:00:00.000Z',
            'custom': {'type': 'user type', 'step': 'user step'},
          };
          final definition = script
              ? WorkflowScript(
                  name: 'metadata.script',
                  run: (script) => script.step('wait', (step) async {
                    if (step.takeResumeData() != null) return 'done';
                    if (event) {
                      await step.awaitEvent('actual.topic', data: data);
                    } else {
                      await step.sleep(const Duration(seconds: 1), data: data);
                    }
                    return 'waiting';
                  }),
                ).definition
              : Flow(
                  name: 'metadata.flow',
                  build: (flow) {
                    flow.step('wait', (context) {
                      if (context.takeResumeData() != null) return 'done';
                      if (event) {
                        context.awaitEvent('actual.topic', data: data);
                      } else {
                        context.sleep(const Duration(seconds: 1), data: data);
                      }
                      return 'waiting';
                    });
                  },
                ).definition;
          runtime.registerWorkflow(definition);
          final id = await runtime.startWorkflow(definition.name);
          await runtime.executeRun(id);
          final metadata = script
              ? (await (store as WorkflowConcurrentStore).listConcurrentSteps(
                  id,
                )).single.suspensionData!
              : (await store.get(id))!.suspensionData!;
          expect(metadata['step'], 'wait');
          expect(metadata['iterationStep'], 'wait');
          expect(metadata['iteration'], 0);
          expect(metadata['type'], event ? 'event' : 'sleep');
          expect(metadata['topic'], event ? 'actual.topic' : isNull);
          expect(metadata['dueAt'], isNull);
          expect(metadata['resumeReason'], isNull);
          expect(metadata['policyDeadline'], isNull);
          expect(metadata['custom'], data['custom']);
          expect(
            await runtime.resumeDueRuns(now: clock.now(), enqueue: false),
            isEmpty,
          );
          if (event) {
            await runtime.emit('actual.topic', const {'ready': true});
          } else {
            clock.advance(const Duration(seconds: 1));
            await runtime.resumeDueRuns(now: clock.now(), enqueue: false);
          }
          await runtime.executeRun(id);
          expect((await store.get(id))!.status, WorkflowStatus.completed);
          expect((await store.get(id))!.result, 'done');
        },
      );
    }
  }

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
