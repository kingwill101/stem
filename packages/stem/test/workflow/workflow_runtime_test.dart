import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBroker broker;
  late InMemoryResultBackend backend;
  late SimpleTaskRegistry registry;
  late Stem stem;
  late InMemoryWorkflowStore store;
  late WorkflowRuntime runtime;

  setUp(() {
    broker = InMemoryBroker();
    backend = InMemoryResultBackend();
    registry = SimpleTaskRegistry();
    stem = Stem(broker: broker, registry: registry, backend: backend);
    store = InMemoryWorkflowStore();
    runtime = WorkflowRuntime(
      stem: stem,
      store: store,
      eventBus: InMemoryEventBus(store),
      pollInterval: const Duration(milliseconds: 25),
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

  test('suspends on sleep and resumes after delay', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'sleep.workflow',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == 'awake') {
              return 'slept';
            }
            context.sleep(
              const Duration(milliseconds: 20),
              data: const {'payload': 'awake'},
            );
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
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await runtime.start(); // ensure timer is running
    final due = await store.dueRuns(DateTime.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'slept-done');
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

  test('sleep then event workflow reaches terminal state', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'durable.sleep.event',
        build: (flow) {
          flow.step('initial', (context) async {
            final resume = context.takeResumeData();
            if (resume != 'awake') {
              context.sleep(
                const Duration(milliseconds: 20),
                data: const {'payload': 'awake'},
              );
              return null;
            }
            return resume;
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

    await Future<void>.delayed(const Duration(milliseconds: 25));
    final due = await store.dueRuns(DateTime.now());
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
}
