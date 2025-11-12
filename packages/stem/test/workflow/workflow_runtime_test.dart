import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBroker broker;
  late InMemoryResultBackend backend;
  late SimpleTaskRegistry registry;
  late Stem stem;
  late InMemoryWorkflowStore store;
  late WorkflowRuntime runtime;
  late FakeWorkflowClock clock;

  setUp(() {
    broker = InMemoryBroker();
    backend = InMemoryResultBackend();
    registry = SimpleTaskRegistry();
    stem = Stem(broker: broker, registry: registry, backend: backend);
    clock = FakeWorkflowClock(DateTime.utc(2024, 1, 1));
    store = InMemoryWorkflowStore(clock: clock);
    runtime = WorkflowRuntime(
      stem: stem,
      store: store,
      eventBus: InMemoryEventBus(store),
      clock: clock,
      pollInterval: const Duration(milliseconds: 25),
      leaseExtension: const Duration(seconds: 5),
    );
    registry.register(runtime.workflowRunnerHandler());
  });

  tearDown(() async {
    await runtime.dispose();
    broker.dispose();
  });

  test('executes workflow and persists results', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'demo.workflow',
        build: (flow) {
          flow.step('prepare', (context) async => 'ready');
          flow.step(
            'finish',
            (context) async => '${context.previousResult}-done',
          );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('demo.workflow');
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(state?.result, 'ready-done');
    expect(await store.readStep(runId, 'prepare'), 'ready');
    expect(await store.readStep(runId, 'finish'), 'ready-done');
  });

  test('extends lease when checkpoints persist', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'lease.workflow',
        build: (flow) {
          flow.step('only', (context) async => 'done');
        },
      ).definition,
    );

    final extendCalls = <Duration>[];
    final context = TaskContext(
      id: 'lease-task',
      attempt: 1,
      headers: <String, String>{},
      meta: <String, Object?>{},
      heartbeat: () {},
      extendLease: (duration) async => extendCalls.add(duration),
      progress: (_, {data}) async {},
    );

    final runId = await runtime.startWorkflow('lease.workflow');
    await runtime.executeRun(runId, taskContext: context);

    expect(extendCalls, isNotEmpty);
    expect(
      extendCalls.every((duration) => duration == runtime.leaseExtension),
      isTrue,
    );
  });

  test('suspends on sleep and resumes after delay', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'sleep.workflow',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == true) {
              return 'slept';
            }
            context.sleep(const Duration(milliseconds: 20));
            return null;
          });
          flow.step(
            'complete',
            (context) async => '${context.previousResult}-done',
          );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('sleep.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.resumeAt, isNotNull);

    // Simulate beat loop discovering the due run.
    clock.advance(const Duration(milliseconds: 30));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'slept-done');
  });

  test('sleep auto resumes without manual guard', () async {
    var iterations = 0;

    runtime.registerWorkflow(
      Flow(
        name: 'sleep.autoresume.workflow',
        build: (flow) {
          flow.step('loop', (context) async {
            iterations += 1;
            if (iterations == 1) {
              context.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('sleep.autoresume.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);

    clock.advance(const Duration(milliseconds: 40));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(iterations, 2);
    expect(completed?.result, 'resumed');
  });

  test('awaitEvent suspends and resumes with payload', () async {
    String? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.workflow',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('user.updated');
              return null;
            }
            final payload = resume as Map<String, Object?>;
            observedPayload = payload['id'] as String?;
            return payload['id'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated');

    await runtime.emit('user.updated', const {'id': 'user-123'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload, 'user-123');
  });

  test('emit persists payload before worker resumes execution', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'event.persisted',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('persist.event');
              return null;
            }
            final payload = resume as Map<String, Object?>;
            return payload['value'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.persisted');
    await runtime.executeRun(runId);

    await runtime.emit('persist.event', const <String, Object?>{
      'value': 'ready',
    });

    final afterEmit = await store.get(runId);
    expect(afterEmit?.status, WorkflowStatus.running);
    expect(afterEmit?.suspensionData?['payload'], {'value': 'ready'});

    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'ready');
  });

  test('saveStep refreshes run heartbeat', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'heartbeat.workflow',
        build: (flow) {
          flow.step('first', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('heartbeat.workflow');
    final initial = await store.get(runId);
    expect(initial?.updatedAt, isNotNull);

    clock.advance(const Duration(milliseconds: 2));
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.updatedAt, isNotNull);
    expect(completed!.updatedAt!.isAfter(initial!.updatedAt!), isTrue);
  });

  test('sleep then event workflow reaches terminal state', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'durable.sleep.event',
        build: (flow) {
          flow.step('initial', (context) async {
            final resume = context.takeResumeData();
            if (resume != true) {
              context.sleep(const Duration(milliseconds: 20));
              return null;
            }
            return 'awake';
          });

          flow.step('await-event', (context) async {
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('demo.event');
              return null;
            }
            final payload = resume as Map<String, Object?>;
            return payload['message'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('durable.sleep.event');
    await runtime.executeRun(runId);

    final afterSleep = await store.get(runId);
    expect(afterSleep?.status, WorkflowStatus.suspended);
    expect(afterSleep?.cursor, 0);
    expect(afterSleep?.resumeAt, isNotNull);

    clock.advance(const Duration(milliseconds: 25));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final awaitingEvent = await store.get(runId);
    expect(awaitingEvent?.status, WorkflowStatus.suspended);
    expect(awaitingEvent?.cursor, 1);
    expect(awaitingEvent?.waitTopic, 'demo.event');

    await runtime.emit('demo.event', const {'message': 'event received'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'event received');
  });

  test('idempotency helper returns stable key across retries', () async {
    int attempts = 0;
    final observedKeys = <String>[];

    runtime.registerWorkflow(
      Flow(
        name: 'idempotency.workflow',
        build: (flow) {
          flow.step('idempotent-call', (context) async {
            final key = context.idempotencyKey('charge');
            observedKeys.add(key);
            if (attempts++ == 0) {
              throw StateError('transient');
            }
            return key;
          });
        },
      ).definition,
    );

    final extendCalls = <Duration>[];
    final context = TaskContext(
      id: 'idempotent-task',
      attempt: 1,
      headers: <String, String>{},
      meta: <String, Object?>{},
      heartbeat: () {},
      extendLease: (duration) async => extendCalls.add(duration),
      progress: (_, {data}) async {},
    );

    final runId = await runtime.startWorkflow('idempotency.workflow');
    await expectLater(
      () => runtime.executeRun(runId, taskContext: context),
      throwsA(isA<StateError>()),
    );

    await runtime.executeRun(runId, taskContext: context);

    expect(observedKeys.length, 2);
    expect(observedKeys.first, observedKeys.last);
    expect(extendCalls, isNotEmpty);
  });

  test('autoVersion stores sequential checkpoints when rewound', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      Flow(
        name: 'repeat.workflow',
        build: (flow) {
          flow.step('repeat', (context) async {
            iterations.add(context.iteration);
            return 'value-${context.iteration}';
          }, autoVersion: true);
          flow.step('tail', (context) async => context.previousResult);
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('repeat.workflow');
    await runtime.executeRun(runId);

    var steps = await store.listSteps(runId);
    expect(iterations, [0]);
    expect(steps.map((s) => s.name), containsAll(['repeat#0', 'tail']));

    await store.rewindToStep(runId, 'repeat');
    final rewoundState = await store.get(runId);
    expect(rewoundState?.status, WorkflowStatus.suspended);
    await runtime.executeRun(runId);

    steps = await store.listSteps(runId);
    expect(iterations, [0, 0]);
    expect(steps.map((s) => s.name), containsAll(['repeat#0', 'tail']));
  });

  test('autoVersion preserves iteration across suspension', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      Flow(
        name: 'await.workflow',
        build: (flow) {
          flow.step('await-step', (context) async {
            iterations.add(context.iteration);
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('loop.event');
              return null;
            }
            return (resume as Map<String, Object?>)['value'];
          }, autoVersion: true);
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('await.workflow');
    await runtime.executeRun(runId);

    // Step should be suspended waiting on event.
    var state = await store.get(runId);
    expect(state?.status, WorkflowStatus.suspended);

    await runtime.emit('loop.event', const {'value': 'done'});
    await runtime.executeRun(runId);

    state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(iterations, [0, 0]);
    final steps = await store.listSteps(runId);
    expect(steps.map((s) => s.name), contains('await-step#0'));
  });

  test('script facade executes sequential steps', () async {
    String? previousSeen;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.basic',
        run: (script) async {
          final first = await script.step('first', (step) async => 'ready');
          final second = await script.step('second', (step) async {
            previousSeen = step.previousResult as String?;
            return '$first-done';
          });
          return second;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.basic');
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(state?.result, 'ready-done');
    expect(previousSeen, 'ready');
    expect(await store.readStep(runId, 'first'), 'ready');
    expect(await store.readStep(runId, 'second'), 'ready-done');
  });

  test('script step sleep suspends and resumes', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.sleep',
        run: (script) async {
          await script.step('wait', (step) async {
            final resume = step.takeResumeData();
            if (resume != true) {
              await step.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'slept';
          });
          return 'done';
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.sleep');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.resumeAt, isNotNull);

    clock.advance(const Duration(milliseconds: 30));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'done');
    expect(await store.readStep(runId, 'wait'), 'slept');
  });

  test('script sleep auto resumes without manual guard', () async {
    var iterations = 0;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.sleep.autoresume',
        run: (script) async {
          return script.step('loop', (step) async {
            iterations += 1;
            if (iterations == 1) {
              await step.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.sleep.autoresume');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);

    clock.advance(const Duration(milliseconds: 40));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(iterations, 2);
    expect(completed?.result, 'resumed');
  });

  test('script awaitEvent resumes with payload', () async {
    Map<String, Object?>? resumePayload;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.event',
        run: (script) async {
          final result = await script.step('wait', (step) async {
            final resume = step.takeResumeData();
            if (resume == null) {
              await step.awaitEvent('user.updated');
              return 'waiting';
            }
            resumePayload = resume as Map<String, Object?>?;
            return resumePayload?['id'];
          });
          return result;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.event');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated');

    await runtime.emit('user.updated', const {'id': 'user-42'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(resumePayload?['id'], 'user-42');
    expect(completed?.result, 'user-42');
  });

  test('script autoVersion step persists sequential checkpoints', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.autoversion',
        run: (script) async {
          for (var i = 0; i < 3; i++) {
            await script.step<int>('repeat', (step) async {
              iterations.add(step.iteration);
              return step.iteration;
            }, autoVersion: true);
          }
          return iterations.length;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.autoversion');
    await runtime.executeRun(runId);

    expect(iterations, [0, 1, 2]);
    expect(await store.readStep(runId, 'repeat#0'), 0);
    expect(await store.readStep(runId, 'repeat#1'), 1);
    expect(await store.readStep(runId, 'repeat#2'), 2);
    final state = await store.get(runId);
    expect(state?.result, 3);
  });

  test('records failures and propagates errors', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'failing.workflow',
        build: (flow) {
          flow.step('boom', (context) async {
            throw StateError('kaboom');
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('failing.workflow');
    await expectLater(
      () => runtime.executeRun(runId),
      throwsA(isA<StateError>()),
    );

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.running);
    expect(state?.lastError?['error'], contains('kaboom'));
  });

  test('cancelWorkflow transitions to cancelled state', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'cancel.workflow',
        build: (flow) {
          flow.step('noop', (context) async => 'noop');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('cancel.workflow');
    await runtime.cancelWorkflow(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
  });

  test('maxRunDuration cancels runs that exceed the limit', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'duration.workflow',
        build: (flow) {
          flow.step('fast', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow(
      'duration.workflow',
      cancellationPolicy: const WorkflowCancellationPolicy(
        maxRunDuration: Duration(milliseconds: 5),
      ),
    );

    clock.advance(const Duration(milliseconds: 15));
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
    expect(state?.cancellationData?['reason'], 'maxRunDuration');
  });

  test('maxSuspendDuration cancels runs that stay suspended', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'suspend.workflow',
        build: (flow) {
          flow.step('sleep', (context) async {
            final resume = context.takeResumeData();
            if (resume != true) {
              context.sleep(const Duration(milliseconds: 100));
              return null;
            }
            return 'done';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow(
      'suspend.workflow',
      cancellationPolicy: const WorkflowCancellationPolicy(
        maxSuspendDuration: Duration(milliseconds: 20),
      ),
    );

    await runtime.executeRun(runId);
    clock.advance(const Duration(milliseconds: 80));
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
    expect(state?.cancellationData?['reason'], 'maxSuspendDuration');
  });
}
