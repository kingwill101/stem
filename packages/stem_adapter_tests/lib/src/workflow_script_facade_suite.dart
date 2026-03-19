import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/workflow_store_contract_suite.dart';
import 'package:test/test.dart';

/// Runs contract tests covering the workflow script facade behavior.
void runWorkflowScriptFacadeTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow script facade', () {
    WorkflowStore? store;
    InMemoryBroker? broker;
    InMemoryResultBackend? backend;
    Stem? stem;
    WorkflowRuntime? runtime;
    late FakeWorkflowClock clock;

    setUp(() async {
      clock = FakeWorkflowClock(DateTime.utc(2024));
      store = await factory.create(clock);
      broker = InMemoryBroker();
      backend = InMemoryResultBackend();
      final currentRegistry = InMemoryTaskRegistry();
      stem = Stem(broker: broker!, registry: currentRegistry, backend: backend);
      runtime = WorkflowRuntime(
        stem: stem!,
        store: store!,
        eventBus: InMemoryEventBus(store!),
        clock: clock,
        pollInterval: const Duration(milliseconds: 50),
      );
      currentRegistry.register(runtime!.workflowRunnerHandler());
    });

    tearDown(() async {
      await runtime?.dispose();
      broker?.dispose();
      final disposer = factory.dispose;
      final currentStore = store;
      if (disposer != null && currentStore != null) {
        await disposer(currentStore);
      }
      store = null;
      broker = null;
      backend = null;
      stem = null;
      runtime = null;
    });

    test('persists sequential steps and final result', () async {
      final currentRuntime = runtime!;
      final currentStore = store!;
      String? previousSeen;

      currentRuntime.registerWorkflow(
        WorkflowScript(
          name: 'script.contract.basic',
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

      final runId = await currentRuntime.startWorkflow('script.contract.basic');
      await currentRuntime.executeRun(runId);

      final state = await currentStore.get(runId);
      expect(state?.status, WorkflowStatus.completed);
      expect(state?.result, 'ready-done');
      expect(previousSeen, 'ready');
      expect(await currentStore.readStep<String>(runId, 'first'), 'ready');
      final secondResult = await currentStore.readStep<String>(runId, 'second');
      expect(secondResult, 'ready-done');
    });

    test('sleep suspends and resumes with stored payload', () async {
      final currentRuntime = runtime!;
      final currentStore = store!;

      currentRuntime.registerWorkflow(
        WorkflowScript(
          name: 'script.contract.sleep',
          run: (script) async {
            await script.step('wait', (step) async {
              final resume = step.takeResumeData();
              if (resume != true) {
                await step.sleep(const Duration(milliseconds: 30));
                return 'waiting';
              }
              return 'slept';
            });
            return 'done';
          },
        ).definition,
      );

      final runId = await currentRuntime.startWorkflow('script.contract.sleep');
      await currentRuntime.executeRun(runId);

      final suspended = await currentStore.get(runId);
      expect(suspended?.status, WorkflowStatus.suspended);
      expect(suspended?.resumeAt, isNotNull);

      clock.advance(const Duration(milliseconds: 40));
      final due = await currentStore.dueRuns(clock.now());
      for (final id in due) {
        final state = await currentStore.get(id);
        await currentStore.markResumed(id, data: state?.suspensionData);
        await currentRuntime.executeRun(id);
      }

      final completed = await currentStore.get(runId);
      expect(completed?.status, WorkflowStatus.completed);
      expect(await currentStore.readStep<String>(runId, 'wait'), 'slept');
    });

    test('autoVersion steps persist sequential checkpoints', () async {
      final currentRuntime = runtime!;
      final currentStore = store!;
      final iterations = <int>[];

      currentRuntime.registerWorkflow(
        WorkflowScript(
          name: 'script.contract.autoversion',
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

      final runId = await currentRuntime.startWorkflow(
        'script.contract.autoversion',
      );
      await currentRuntime.executeRun(runId);

      expect(iterations, [0, 1, 2]);
      expect(await currentStore.readStep<int>(runId, 'repeat#0'), 0);
      expect(await currentStore.readStep<int>(runId, 'repeat#1'), 1);
      expect(await currentStore.readStep<int>(runId, 'repeat#2'), 2);
      final state = await currentStore.get(runId);
      expect(state?.result, 3);
    });

    test('awaitEvent resumes with payload', () async {
      final currentRuntime = runtime!;
      final currentStore = store!;
      Map<String, Object?>? observed;

      currentRuntime.registerWorkflow(
        WorkflowScript(
          name: 'script.contract.event',
          run: (script) async {
            final result = await script.step('wait', (step) async {
              final resume = step.takeResumeData();
              if (resume == null) {
                await step.awaitEvent('contract.event');
                return 'waiting';
              }
              observed = resume as Map<String, Object?>?;
              return observed?['value'];
            });
            return result;
          },
        ).definition,
      );

      final runId = await currentRuntime.startWorkflow('script.contract.event');
      await currentRuntime.executeRun(runId);

      final suspended = await currentStore.get(runId);
      expect(suspended?.status, WorkflowStatus.suspended);
      expect(suspended?.waitTopic, 'contract.event');

      await currentRuntime.emit('contract.event', const {'value': 'resumed'});
      await currentRuntime.executeRun(runId);

      final completed = await currentStore.get(runId);
      expect(completed?.status, WorkflowStatus.completed);
      expect(observed?['value'], 'resumed');
      expect(completed?.result, 'resumed');
    });

    test(
      'event resumptions enqueue continuations onto the '
      'persisted queue metadata',
      () async {
        final currentStem = stem!;
        final currentStore = store!;
        final currentBroker = broker!;
        final runtimeA = WorkflowRuntime(
          stem: currentStem,
          store: currentStore,
          eventBus: InMemoryEventBus(currentStore),
          clock: clock,
          queue: 'workflow-a',
          continuationQueue: 'workflow-a-cont',
          executionQueue: 'workflow-a-exec',
        );
        final runtimeB = WorkflowRuntime(
          stem: currentStem,
          store: currentStore,
          eventBus: InMemoryEventBus(currentStore),
          clock: clock,
          queue: 'workflow-b',
          continuationQueue: 'workflow-b-cont',
          executionQueue: 'workflow-b-exec',
        );

        final definition = WorkflowScript(
          name: 'script.contract.queue-routing',
          run: (script) async {
            final value = await script.step<String>('wait', (step) async {
              final resume = step.takeResumeData();
              if (resume == null) {
                await step.awaitEvent('contract.queue-routing');
                return 'waiting';
              }
              final payload = resume as Map<String, Object?>;
              return payload['value']?.toString() ?? 'missing';
            });
            return value;
          },
        ).definition;
        runtimeA.registerWorkflow(definition);
        runtimeB.registerWorkflow(definition);

        Future<Delivery?> nextDelivery(String queue) async {
          try {
            return await currentBroker
                .consume(RoutingSubscription.singleQueue(queue))
                .first
                .timeout(const Duration(milliseconds: 250));
          } on TimeoutException {
            return null;
          }
        }

        try {
          final runId = await runtimeA.startWorkflow(
            'script.contract.queue-routing',
          );
          await runtimeA.executeRun(runId);

          final suspended = await currentStore.get(runId);
          expect(suspended?.status, WorkflowStatus.suspended);
          expect(suspended?.waitTopic, 'contract.queue-routing');
          expect(suspended?.continuationQueue, 'workflow-a-cont');
          expect(
            suspended?.executionQueue,
            'workflow-a-exec',
          );

          final deliveryAFuture = nextDelivery('workflow-a-cont');
          final deliveryBFuture = nextDelivery('workflow-b-cont');

          await runtimeB.emit('contract.queue-routing', const {'value': 'ok'});

          final deliveryA = await deliveryAFuture;
          final deliveryB = await deliveryBFuture;

          expect(deliveryA, isNotNull);
          expect(deliveryB, isNull);
          expect(deliveryA!.envelope.queue, 'workflow-a-cont');
          expect(
            deliveryA.envelope.meta['stem.workflow.orchestrationQueue'],
            'workflow-a',
          );
          expect(
            deliveryA.envelope.meta['stem.workflow.continuationQueue'],
            'workflow-a-cont',
          );
          expect(
            deliveryA.envelope.meta['stem.workflow.executionQueue'],
            'workflow-a-exec',
          );
          expect(
            deliveryA.envelope.meta['stem.workflow.continuationReason'],
            WorkflowContinuationReason.event.name,
          );
        } finally {
          await runtimeA.dispose();
          await runtimeB.dispose();
        }
      },
    );
  });
}
