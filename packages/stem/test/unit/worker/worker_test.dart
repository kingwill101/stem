import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:contextual/contextual.dart' show Level, LogDriver, LogEntry;
import 'package:stem/memory.dart';
import 'package:stem/src/observability/logging.dart' show stemLogger;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Worker', () {
    test(
      'recovers an acknowledgement failure without re-executing',
      () async {
        final broker = _AckFailingBroker();
        final backend = InMemoryResultBackend();
        var executions = 0;
        final task = _CountingSuccessTask(() => executions += 1);
        final worker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'ack-recovery-worker',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await worker.start();
        final stem = Stem(
          broker: broker,
          backend: backend,
          tasks: [task],
        );
        final taskId = await stem.enqueue(task.name);

        await _waitForTaskState(backend, taskId, TaskState.succeeded);
        await _waitFor(() => broker.ackAttempts >= 2);
        expect(executions, equals(1));

        await worker.shutdown();
        broker.dispose();
      },
    );

    test(
      'keeps the lease alive until terminal acknowledgement completes',
      () async {
        final broker = _BlockingAckBroker();
        final backend = InMemoryResultBackend();
        final task = _CountingSuccessTask(() {});
        final worker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'terminal-ack-lease-worker',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await worker.start();
        try {
          final stem = Stem(
            broker: broker,
            backend: backend,
            tasks: [task],
          );
          final taskId = await stem.enqueue(
            task.name,
            options: const TaskOptions(
              visibilityTimeout: Duration(milliseconds: 80),
            ),
          );

          await broker.ackStarted.future.timeout(const Duration(seconds: 2));
          await _waitFor(
            () => broker.leaseExtensions > 0,
          );
          expect((await backend.get(taskId))?.state, TaskState.succeeded);

          broker.releaseAcknowledgement();
          await broker.ackCompleted.future.timeout(const Duration(seconds: 2));
        } finally {
          broker.releaseAcknowledgement();
          await worker.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'starts lease renewal before consume middleware completes',
      () async {
        final broker = _BlockingConsumeBroker();
        final backend = InMemoryResultBackend();
        final middleware = _BlockingConsumeMiddleware();
        final task = _CountingSuccessTask(() {});
        final worker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          middleware: [middleware],
          consumerName: 'consume-lease-worker',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await worker.start();
        try {
          final stem = Stem(
            broker: broker,
            backend: backend,
            tasks: [task],
          );
          final taskId = await stem.enqueue(
            task.name,
            options: const TaskOptions(
              visibilityTimeout: Duration(milliseconds: 80),
            ),
          );

          await middleware.started.future.timeout(const Duration(seconds: 2));
          await _waitFor(() => broker.leaseExtensions > 0);
          middleware.release();
          await _waitForTaskState(backend, taskId, TaskState.succeeded);
        } finally {
          middleware.release();
          await worker.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'suppresses a duplicate delivery while the original is active',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 5),
        );
        final backend = InMemoryResultBackend();
        final task = _BlockingSuccessTask();
        final worker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'duplicate-suppression-worker',
          concurrency: 2,
          prefetchMultiplier: 1,
        );

        await worker.start();
        try {
          final envelope = Envelope(
            id: 'duplicate-delivery-task',
            name: task.name,
            args: const {},
          );
          await broker.publish(envelope);
          await broker.publish(envelope);

          await task.started.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(task.calls, equals(1));

          task.release();
          await _waitForTaskState(
            backend,
            envelope.id,
            TaskState.succeeded,
          );
        } finally {
          task.release();
          await worker.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'does not let a late cross-worker terminal write overwrite the winner',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 5),
        );
        final backend = _DelayedTerminalBackend();
        final task = _SequencedSuccessTask();
        final firstWorker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'terminal-race-worker-1',
          concurrency: 1,
          prefetchMultiplier: 1,
        );
        final secondWorker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'terminal-race-worker-2',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await firstWorker.start();
        await secondWorker.start();
        try {
          final envelope = Envelope(
            id: 'cross-worker-terminal-race',
            name: task.name,
            args: const {},
          );
          await backend.set(envelope.id, TaskState.queued);
          await broker.publish(envelope);
          await broker.publish(envelope);

          await backend.firstTerminalEntered.future.timeout(
            const Duration(seconds: 2),
          );
          await _waitFor(() => backend.terminalCalls >= 2);
          backend.releaseFirstTerminal();

          await _waitForTaskState(
            backend,
            envelope.id,
            TaskState.succeeded,
          );
          expect((await backend.get(envelope.id))?.payload, 'result-2');
          expect(task.calls, equals(2));
        } finally {
          backend.releaseFirstTerminal();
          await firstWorker.shutdown();
          await secondWorker.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'redelivers after lease loss and preserves the later terminal result',
      () async {
        final broker = _LeaseLossBroker();
        final backend = InMemoryResultBackend();
        final task = _LeaseLossTask();
        final firstWorker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'lease-loss-worker-1',
          concurrency: 1,
          prefetchMultiplier: 1,
        );
        final secondWorker = Worker(
          broker: broker,
          backend: backend,
          tasks: [task],
          consumerName: 'lease-loss-worker-2',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await firstWorker.start();
        await secondWorker.start();
        try {
          final stem = Stem(
            broker: broker,
            backend: backend,
            tasks: [task],
          );
          final taskId = await stem.enqueue(
            task.name,
            options: const TaskOptions(
              visibilityTimeout: Duration(milliseconds: 80),
            ),
          );

          await task.firstStarted.future.timeout(const Duration(seconds: 2));
          await task.secondStarted.future.timeout(const Duration(seconds: 3));
          await _waitFor(
            () async => (await backend.get(taskId))?.payload == 'result-2',
          );

          task.releaseFirst();
          await _waitForTaskState(backend, taskId, TaskState.succeeded);

          expect((await backend.get(taskId))?.payload, 'result-2');
          expect(task.calls, equals(2));
        } finally {
          task.releaseFirst();
          await firstWorker.shutdown();
          await secondWorker.shutdown();
          broker.dispose();
        }
      },
    );

    test('executes task and records success', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final worker = Worker(
        broker: broker,
        backend: backend,
        tasks: [_SuccessTask()],
        consumerName: 'worker-1',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        backend: backend,
        tasks: [_SuccessTask()],
      );
      final taskId = await stem.enqueue('tasks.success');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final running = await backend.get(taskId);
      expect(running?.state, isNotNull);

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final event = events.firstWhere(
        (e) => e.type == WorkerEventType.completed && e.envelope?.id == taskId,
      );

      expect(event.envelope?.id, equals(taskId));
      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('includes workflow metadata in task lifecycle logs', () async {
      final driver = _RecordingLogDriver();
      stemLogger
        ..addChannel(
          'worker-log-test-${DateTime.now().microsecondsSinceEpoch}',
          driver,
        )
        ..setLevel(Level.debug);

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-log-metadata',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue(
        'tasks.success',
        meta: const {
          'stem.workflow.channel': 'orchestration',
          'stem.workflow.continuation': true,
          'stem.workflow.continuationReason': 'due',
          'stem.workflow.runId': 'run-123',
          'stem.workflow.id': 'wf-123',
          'stem.workflow.name': 'demo.workflow',
          'stem.workflow.step': 'wait',
          'stem.workflow.stepIndex': 2,
          'stem.workflow.iteration': 1,
        },
      );

      await _waitForTaskState(backend, taskId, TaskState.succeeded);
      await Future<void>.delayed(Duration.zero);

      LogEntry startedEntry() => driver.entries.firstWhere(
        (entry) =>
            entry.record.message == 'Task {task} started' &&
            entry.record.context.all()['id'] == taskId,
      );

      LogEntry succeededEntry() => driver.entries.firstWhere(
        (entry) =>
            entry.record.message == 'Task {task} succeeded' &&
            entry.record.context.all()['id'] == taskId,
      );

      for (final entry in [startedEntry(), succeededEntry()]) {
        final context = entry.record.context.all();
        expect(context['workflowChannel'], equals('orchestration'));
        expect(context['workflowContinuation'], isTrue);
        expect(context['workflowReason'], equals('due'));
        expect(context['workflowRunId'], equals('run-123'));
        expect(context['workflowId'], equals('wf-123'));
        expect(context['workflow'], equals('demo.workflow'));
        expect(context['workflowStep'], equals('wait'));
        expect(context['workflowStepIndex'], equals(2));
        expect(context['workflowIteration'], equals(1));
      }

      await worker.shutdown();
      broker.dispose();
    });

    test('dispatches chord callback when body completes', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(_ChordBodyTask())
        ..register(_ChordCallbackTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'chord-worker',
        concurrency: 2,
        prefetchMultiplier: 1,
      );

      await worker.start();

      final canvas = Canvas(
        broker: broker,
        backend: backend,
        registry: registry,
      );

      final chordResult = await canvas.chord<int>(
        body: [
          task<int>('tasks.body', args: const {'value': 2}),
          task<int>('tasks.body', args: const {'value': 5}),
        ],
        callback: task('tasks.chord.callback'),
      );

      await _waitForCallbackSuccess(backend, chordResult.callbackTaskId);
      final status = await backend.get(chordResult.callbackTaskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.payload, equals(7));
      expect(status?.meta['chordResults'], equals([2, 5]));

      await worker.shutdown();
      broker.dispose();
    });

    test('releases unique lock after task completion', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final coordinator = UniqueTaskCoordinator(
        lockStore: InMemoryLockStore(),
        defaultTtl: const Duration(seconds: 5),
      );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'unique-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
        uniqueTaskCoordinator: coordinator,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
        uniqueTaskCoordinator: coordinator,
      );

      const options = TaskOptions(
        unique: true,
        uniqueFor: Duration(seconds: 5),
      );
      final firstId = await stem.enqueue('tasks.success', options: options);

      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == firstId,
        ),
      );

      final secondId = await stem.enqueue('tasks.success', options: options);
      expect(secondId, isNot(firstId));

      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == secondId,
        ),
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('emits task lifecycle signals for successful execution', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'signal-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final calls = <String>[];
      final received = Completer<void>();
      final succeeded = Completer<void>();
      final postrun = Completer<void>();

      final subscriptions = <SignalSubscription>[
        StemSignals.taskReceived.connect((payload, _) {
          if (payload.envelope.name == 'tasks.success') {
            calls.add('received');
            received.complete();
          }
        }),
        StemSignals.taskPrerun.connect((payload, _) {
          if (payload.envelope.name == 'tasks.success') {
            calls.add('prerun');
          }
        }),
        StemSignals.taskPostrun.connect((payload, _) {
          if (payload.envelope.name == 'tasks.success') {
            calls.add('postrun:${payload.state.name}');
            if (!postrun.isCompleted) {
              postrun.complete();
            }
          }
        }),
        StemSignals.taskSucceeded.connect((payload, _) {
          if (payload.envelope.name == 'tasks.success') {
            calls.add('success');
            if (!succeeded.isCompleted) {
              succeeded.complete();
            }
          }
        }),
      ];

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.success');

      await received.future.timeout(const Duration(seconds: 2));
      await succeeded.future.timeout(const Duration(seconds: 2));
      await postrun.future.timeout(const Duration(seconds: 2));

      expect(
        calls,
        equals(['received', 'prerun', 'success', 'postrun:succeeded']),
      );

      for (final sub in subscriptions) {
        sub.cancel();
      }
      await worker.shutdown();
      broker.dispose();
    });

    test('emits worker heartbeat signals', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'heartbeat-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
        workerHeartbeatInterval: const Duration(milliseconds: 100),
        heartbeatTransport: const NoopHeartbeatTransport(),
      );

      final heartbeat = Completer<WorkerHeartbeatPayload>();
      final subs = <SignalSubscription>[
        StemSignals.workerHeartbeat.connect((payload, _) {
          if (payload.worker.id == 'heartbeat-worker' &&
              !heartbeat.isCompleted) {
            heartbeat.complete(payload);
          }
        }),
      ];

      await worker.start();

      await heartbeat.future.timeout(const Duration(seconds: 2));

      for (final sub in subs) {
        sub.cancel();
      }
      await worker.shutdown();
      broker.dispose();
    });

    test('autoscaler scales concurrency up and down', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.autoscale',
            entrypoint: _autoscaleEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-autoscale',
        concurrency: 4,
        prefetchMultiplier: 1,
        autoscale: const WorkerAutoscaleConfig(
          enabled: true,
          minConcurrency: 1,
          maxConcurrency: 4,
          tick: Duration(milliseconds: 40),
          idlePeriod: Duration(milliseconds: 120),
          scaleUpCooldown: Duration(milliseconds: 40),
          scaleDownCooldown: Duration(milliseconds: 40),
        ),
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );
      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      for (var i = 0; i < 6; i++) {
        await stem.enqueue('tasks.autoscale');
      }

      await _waitFor(
        () => worker.activeConcurrency >= 3,
      );
      expect(worker.activeConcurrency, greaterThanOrEqualTo(3));

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            6,
        timeout: const Duration(seconds: 5),
      );

      await _waitFor(
        () => worker.activeConcurrency == 1,
        timeout: const Duration(seconds: 10),
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('emits worker lifecycle signals on start and shutdown', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-life',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final phases = <String>[];
      final init = Completer<void>();
      final ready = Completer<void>();
      final stopping = Completer<void>();
      final shutdown = Completer<void>();

      final subscriptions = <SignalSubscription>[
        StemSignals.workerInit.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('init');
            init.complete();
          }
        }),
        StemSignals.workerReady.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('ready');
            ready.complete();
          }
        }),
        StemSignals.workerStopping.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('stopping:${payload.reason}');
            stopping.complete();
          }
        }),
        StemSignals.workerShutdown.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('shutdown:${payload.reason}');
            shutdown.complete();
          }
        }),
      ];

      await worker.start();

      await init.future.timeout(const Duration(seconds: 2));
      await ready.future.timeout(const Duration(seconds: 2));

      await worker.shutdown(mode: WorkerShutdownMode.soft);

      await stopping.future.timeout(const Duration(seconds: 2));
      await shutdown.future.timeout(const Duration(seconds: 2));

      expect(
        phases,
        equals(['init', 'ready', 'stopping:soft', 'shutdown:soft']),
      );

      for (final sub in subscriptions) {
        sub.cancel();
      }

      broker.dispose();
    });

    test('emits worker child lifecycle signals', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.isolate',
            entrypoint: _isolateEntrypoint,
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'isolate-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final init = Completer<int>();
      final shutdown = Completer<int>();
      final events = <WorkerEvent>[];
      final eventSub = worker.events.listen(events.add);
      final subscriptions = <SignalSubscription>[
        StemSignals.workerChildInit.connect((payload, _) {
          if (payload.worker.id == 'isolate-worker' && !init.isCompleted) {
            init.complete(payload.isolateId);
          }
        }),
        StemSignals.workerChildShutdown.connect((payload, _) {
          if (payload.worker.id == 'isolate-worker' && !shutdown.isCompleted) {
            shutdown.complete(payload.isolateId);
          }
        }),
      ];

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.isolate', args: {'value': 2});

      final spawnedId = await init.future.timeout(const Duration(seconds: 2));

      await _waitFor(
        () => events.any((event) => event.type == WorkerEventType.completed),
        timeout: const Duration(seconds: 4),
      );

      await worker.shutdown();
      final shutdownId = await shutdown.future.timeout(
        const Duration(seconds: 2),
      );

      expect(shutdownId, equals(spawnedId));

      for (final sub in subscriptions) {
        sub.cancel();
      }

      await eventSub.cancel();

      broker.dispose();
    });
    test('emits worker lifecycle signals on start and shutdown', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-life',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final phases = <String>[];
      final init = Completer<void>();
      final ready = Completer<void>();
      final stopping = Completer<void>();
      final shutdown = Completer<void>();

      final subscriptions = <SignalSubscription>[
        StemSignals.workerInit.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('init');
            init.complete();
          }
        }),
        StemSignals.workerReady.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('ready');
            ready.complete();
          }
        }),
        StemSignals.workerStopping.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('stopping:${payload.reason}');
            stopping.complete();
          }
        }),
        StemSignals.workerShutdown.connect((payload, _) {
          if (payload.worker.id == 'worker-life') {
            phases.add('shutdown:${payload.reason}');
            shutdown.complete();
          }
        }),
      ];

      await worker.start();

      await init.future.timeout(const Duration(seconds: 2));
      await ready.future.timeout(const Duration(seconds: 2));

      await worker.shutdown(mode: WorkerShutdownMode.soft);

      await stopping.future.timeout(const Duration(seconds: 2));
      await shutdown.future.timeout(const Duration(seconds: 2));

      expect(
        phases,
        equals(['init', 'ready', 'stopping:soft', 'shutdown:soft']),
      );

      for (final sub in subscriptions) {
        sub.cancel();
      }

      broker.dispose();
    });

    test('emits retry signal when task is retried', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_FlakyTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-retry',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final retrySeen = Completer<TaskRetryPayload>();
      final postrunStates = <String>[];
      final subscriptions = <SignalSubscription>[
        StemSignals.taskRetry.connect((payload, _) {
          if (payload.envelope.name == 'tasks.flaky' &&
              !retrySeen.isCompleted) {
            retrySeen.complete(payload);
          }
        }),
        StemSignals.taskPostrun.connect((payload, _) {
          if (payload.envelope.name == 'tasks.flaky') {
            postrunStates.add(payload.state.name);
          }
        }),
      ];

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.flaky');

      final payload = await retrySeen.future.timeout(
        const Duration(seconds: 2),
      );
      expect(payload.reason, isA<StateError>());

      await _waitFor(
        () => postrunStates.contains('succeeded'),
        timeout: const Duration(seconds: 4),
      );

      expect(postrunStates, contains('retried'));
      expect(postrunStates, contains('succeeded'));

      for (final sub in subscriptions) {
        sub.cancel();
      }

      await worker.shutdown();
      broker.dispose();
    });

    test('consumes tasks across multiple subscribed queues', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.default',
            entrypoint: (context, args) async {
              return;
            },
            options: const TaskOptions(maxRetries: 1),
          ),
        )
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.priority',
            entrypoint: (context, args) async {
              return;
            },
            options: const TaskOptions(queue: 'priority', maxRetries: 1),
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        subscription: RoutingSubscription(
          queues: const ['default', 'priority'],
        ),
        consumerName: 'worker-multi',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      expect(worker.subscriptionQueues, containsAll(['default', 'priority']));

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.default');
      await stem.enqueue(
        'tasks.priority',
        options: const TaskOptions(queue: 'priority'),
      );

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 5),
      );

      final completedQueues = events
          .where((event) => event.type == WorkerEventType.completed)
          .map((event) => event.envelope?.queue)
          .whereType<String>()
          .toSet();

      expect(completedQueues, contains('default'));
      expect(completedQueues, contains('priority'));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('warm shutdown drains tasks', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.sleepy',
            entrypoint: _sleepyEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-warm-shutdown',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );
      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.sleepy');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      await worker.shutdown(mode: WorkerShutdownMode.warm);

      expect(
        events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == taskId,
        ),
        isTrue,
      );
      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      await sub.cancel();
      broker.dispose();
    });

    test('max tasks per isolate triggers recycle', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.recycle',
            entrypoint: _isolateHashEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-recycle',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
          maxTasksPerIsolate: 1,
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final first = await stem.enqueue('tasks.recycle');
      final second = await stem.enqueue('tasks.recycle');

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 3),
      );

      final firstStatus = await backend.get(first);
      final secondStatus = await backend.get(second);
      expect(firstStatus?.payload, isNotNull);
      expect(secondStatus?.payload, isNotNull);
      expect(firstStatus?.payload, isNot(equals(secondStatus?.payload)));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('memory recycle threshold replaces isolate', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.memory-recycle',
            entrypoint: _isolateHashEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-memory-recycle',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
          maxMemoryPerIsolateBytes: 1,
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final first = await stem.enqueue('tasks.memory-recycle');
      final second = await stem.enqueue('tasks.memory-recycle');

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 3),
      );

      final firstStatus = await backend.get(first);
      final secondStatus = await backend.get(second);
      expect(firstStatus?.payload, isNotNull);
      expect(secondStatus?.payload, isNotNull);
      expect(firstStatus?.payload, isNot(equals(secondStatus?.payload)));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('verifies signed tasks succeed end-to-end', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());

      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('signing-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      final producerSigner = PayloadSigner(signingConfig);
      final verifierSigner = PayloadSigner(signingConfig);

      final workerEvents = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-signed',
        concurrency: 1,
        prefetchMultiplier: 1,
        signer: verifierSigner,
      );
      final sub = worker.events.listen(workerEvents.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
        signer: producerSigner,
      );

      final taskId = await stem.enqueue('tasks.success');

      await _waitFor(
        () => workerEvents.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);

      final dead = await broker.listDeadLetters('default');
      expect(dead.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('routes tampered signatures to dead letters', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());

      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('signing-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      final producerSigner = PayloadSigner(signingConfig);
      final verifierSigner = PayloadSigner(signingConfig);

      final workerEvents = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-signed-invalid',
        concurrency: 1,
        prefetchMultiplier: 1,
        signer: verifierSigner,
      );
      final sub = worker.events.listen(workerEvents.add);

      await worker.start();

      final envelope = Envelope(name: 'tasks.success', args: const {});
      final signed = await producerSigner.sign(envelope);
      final tampered = signed.copyWith(args: const {'tampered': true});
      await broker.publish(tampered);

      await _waitFor(
        () => workerEvents.any(
          (event) =>
              event.type == WorkerEventType.failed &&
              event.envelope?.id == tampered.id,
        ),
      );

      final status = await backend.get(tampered.id);
      expect(status?.state, TaskState.failed);

      final dead = await broker.listDeadLetters('default');
      expect(dead.entries, hasLength(1));
      expect(dead.entries.single.envelope.id, tampered.id);
      expect(dead.entries.single.reason, equals('signature-invalid'));

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('retries failing task then succeeds', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_FlakyTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-2',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.flaky');

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );
      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.attempt, equals(1));

      expect(
        events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
        isTrue,
      );

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('retries signed failing task then succeeds', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_FlakyTask());

      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('signing-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      final producerSigner = PayloadSigner(signingConfig);
      final verifierSigner = PayloadSigner(signingConfig);

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-signed-retry',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
        signer: verifierSigner,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(
        broker: broker,
        registry: registry,
        backend: backend,
        signer: producerSigner,
      );
      final taskId = await stem.enqueue('tasks.flaky');

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );
      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.attempt, equals(1));

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('moves task to dead letter after max retries', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_AlwaysFailTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-3',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      final failureSignal = Completer<TaskFailurePayload>();
      final postrunStates = <String>[];
      final subscriptions = <SignalSubscription>[
        StemSignals.taskFailed.connect((payload, _) {
          if (payload.envelope.name == 'tasks.fail' &&
              !failureSignal.isCompleted) {
            failureSignal.complete(payload);
          }
        }),
        StemSignals.taskPostrun.connect((payload, _) {
          if (payload.envelope.name == 'tasks.fail') {
            postrunStates.add(payload.state.name);
          }
        }),
      ];

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.fail');

      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.failed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.failed);

      await failureSignal.future.timeout(const Duration(seconds: 2));
      expect(postrunStates, contains('failed'));

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, hasLength(1));
      expect(deadPage.entries.single.envelope.id, equals(taskId));

      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('bounds a retry storm at each task retry budget', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 2),
        claimInterval: const Duration(milliseconds: 5),
      );
      final backend = InMemoryResultBackend();
      final task = _RetryStormTask();
      final registry = InMemoryTaskRegistry()..register(task);
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'retry-storm-worker',
        concurrency: 4,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 1),
          max: const Duration(milliseconds: 2),
          seed: 1,
        ),
      );
      const totalTasks = 12;
      final taskIds = <String>[];

      await worker.start();
      try {
        final stem = Stem(broker: broker, registry: registry, backend: backend);
        for (var index = 0; index < totalTasks; index++) {
          taskIds.add(
            await stem.enqueue(
              task.name,
              args: {'job': index},
            ),
          );
        }

        await _waitFor(
          () async {
            final dead = await broker.listDeadLetters('default');
            return dead.entries.length == totalTasks;
          },
          timeout: const Duration(seconds: 5),
        );

        for (final taskId in taskIds) {
          expect((await backend.get(taskId))?.state, TaskState.failed);
        }
        expect(task.calls, equals(totalTasks * 4));
        expect(await broker.pendingCount('default'), equals(0));
        expect(await broker.inflightCount('default'), equals(0));
      } finally {
        await worker.shutdown();
        broker.dispose();
      }
    });

    test('dead-letters malformed payloads without retrying them', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
      );
      final backend = InMemoryResultBackend();
      final task = _PoisonPayloadTask();
      final registry = InMemoryTaskRegistry()..register(task);
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'poison-payload-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      try {
        final stem = Stem(broker: broker, registry: registry, backend: backend);
        final taskId = await stem.enqueue(
          task.name,
          args: const {'value': 'poison'},
        );

        await _waitForTaskState(backend, taskId, TaskState.failed);
        final dead = await broker.listDeadLetters('default');
        expect(dead.entries, hasLength(1));
        expect(dead.entries.single.reason, equals('invalid-payload'));
        expect(task.calls, equals(0));

        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(task.calls, equals(0));
        expect(
          (await broker.listDeadLetters('default')).entries,
          hasLength(1),
        );
      } finally {
        await worker.shutdown();
        broker.dispose();
      }
    });

    test('executes handler inside isolate when entrypoint provided', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<int>(
            name: 'tasks.isolate',
            entrypoint: _isolateEntrypoint,
            options: const TaskOptions(maxRetries: 1),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-isolate',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.isolate', args: {'value': 7});

      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.payload, equals(14));

      expect(
        events.any((e) => e.type == WorkerEventType.progress),
        isTrue,
        reason: 'expected isolate task to emit progress',
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('enforces hard time limit for isolate tasks', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<String>(
            name: 'tasks.hard-limit',
            entrypoint: _hardLimitEntrypoint,
            options: const TaskOptions(
              maxRetries: 1,
              hardTimeLimit: Duration(milliseconds: 30),
            ),
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-timeout',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 10),
        ),
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.hard-limit');

      await _waitFor(
        () => events.any(
          (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
        ),
      );
      await _waitFor(
        () => events.any(
          (e) =>
              e.type == WorkerEventType.completed && e.envelope?.id == taskId,
        ),
      );

      final retryEvent = events.firstWhere(
        (e) => e.type == WorkerEventType.retried && e.envelope?.id == taskId,
      );
      expect(retryEvent.error, isA<TimeoutException>());

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.succeeded);
      expect(status?.attempt, equals(1));

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, isEmpty);

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test(
      'inline hard time limits stop awaiting but do not cancel handler work',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 10),
          claimInterval: const Duration(milliseconds: 40),
        );
        final backend = InMemoryResultBackend();
        final handlerFinished = Completer<void>();
        var underlyingCompletions = 0;
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<void>.inline(
              name: 'tasks.inline-hard-limit',
              options: const TaskOptions(
                hardTimeLimit: Duration(milliseconds: 20),
              ),
              entrypoint: (context, args) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                underlyingCompletions++;
                handlerFinished.complete();
                return null;
              },
            ),
          );
        final worker = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'worker-inline-timeout',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await worker.start();
        final stem = Stem(broker: broker, registry: registry, backend: backend);
        final taskId = await stem.enqueue('tasks.inline-hard-limit');

        await _waitForTaskState(backend, taskId, TaskState.failed);
        expect(underlyingCompletions, 0);

        await handlerFinished.future.timeout(const Duration(seconds: 1));
        expect(underlyingCompletions, 1);

        await worker.shutdown();
        broker.dispose();
      },
    );

    test(
      'hard shutdown requeues an active isolate delivery '
      'for a replacement worker',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 20),
        );
        final backend = InMemoryResultBackend();
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<int>(
              name: 'tasks.shutdown-requeue',
              entrypoint: _shutdownRequeueEntrypoint,
              options: const TaskOptions(maxRetries: 1),
            ),
          );
        final workerA = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'worker-shutdown-a',
          concurrency: 1,
          prefetchMultiplier: 1,
          lifecycle: const WorkerLifecycleConfig(
            installSignalHandlers: false,
          ),
        );
        final workerB = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'worker-shutdown-b',
          concurrency: 1,
          prefetchMultiplier: 1,
          lifecycle: const WorkerLifecycleConfig(
            installSignalHandlers: false,
          ),
        );

        try {
          await workerA.start();
          final stem = Stem(
            broker: broker,
            registry: registry,
            backend: backend,
          );
          final taskId = await stem.enqueue('tasks.shutdown-requeue');

          await _waitForTaskState(backend, taskId, TaskState.running);
          await workerA.shutdown();

          await workerB.start();
          await _waitForTaskState(backend, taskId, TaskState.succeeded);
          expect((await backend.get(taskId))?.payload, isA<int>());
        } finally {
          await workerA.shutdown();
          await workerB.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'hard shutdown requeues the full prefetched batch for a replacement',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 5),
        );
        final backend = InMemoryResultBackend();
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<String>(
              name: 'tasks.prefetch-shutdown',
              entrypoint: _prefetchShutdownEntrypoint,
              options: const TaskOptions(maxRetries: 1),
            ),
          );
        final workerA = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'prefetch-shutdown-a',
          concurrency: 2,
          prefetch: 6,
          lifecycle: const WorkerLifecycleConfig(
            installSignalHandlers: false,
          ),
        );
        final workerB = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'prefetch-shutdown-b',
          concurrency: 6,
          prefetch: 6,
          lifecycle: const WorkerLifecycleConfig(
            installSignalHandlers: false,
          ),
        );
        const totalTasks = 12;
        final taskIds = <String>[];

        try {
          await workerA.start();
          final stem = Stem(
            broker: broker,
            registry: registry,
            backend: backend,
          );
          for (var index = 0; index < totalTasks; index++) {
            taskIds.add(
              await stem.enqueue(
                'tasks.prefetch-shutdown',
                args: {'index': index},
              ),
            );
          }

          await _waitFor(
            () async => (await broker.inflightCount('default')) == 6,
            timeout: const Duration(seconds: 3),
          );
          await workerA.shutdown();

          expect(await broker.inflightCount('default'), equals(0));
          expect(await broker.pendingCount('default'), equals(totalTasks));

          await workerB.start();
          await _waitFor(
            () async {
              for (final taskId in taskIds) {
                if ((await backend.get(taskId))?.state != TaskState.succeeded) {
                  return false;
                }
              }
              return true;
            },
            timeout: const Duration(seconds: 8),
          );
        } finally {
          await workerA.shutdown();
          await workerB.shutdown();
          broker.dispose();
        }
      },
    );

    test(
      'late inline completion cannot write to the closed event stream',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 20),
        );
        final backend = InMemoryResultBackend();
        final entered = Completer<void>();
        final release = Completer<void>();
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<void>.inline(
              name: 'tasks.late-inline-completion',
              options: const TaskOptions(
                softTimeLimit: Duration(milliseconds: 10),
              ),
              entrypoint: (context, args) async {
                if (!entered.isCompleted) entered.complete();
                await release.future;
                return null;
              },
            ),
          );
        final worker = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          consumerName: 'worker-late-inline-completion',
          concurrency: 1,
          prefetchMultiplier: 1,
          heartbeatInterval: const Duration(milliseconds: 5),
          lifecycle: const WorkerLifecycleConfig(
            installSignalHandlers: false,
          ),
        );
        final events = <WorkerEvent>[];
        final subscription = worker.events.listen(events.add);

        try {
          await worker.start();
          final stem = Stem(
            broker: broker,
            registry: registry,
            backend: backend,
          );
          await stem.enqueue('tasks.late-inline-completion');
          await entered.future.timeout(const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 25));

          await worker.shutdown();
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 100));

          expect(events, isNotEmpty);
        } finally {
          if (!release.isCompleted) release.complete();
          await subscription.cancel();
          await worker.shutdown();
          broker.dispose();
        }
      },
    );

    test('skips revoked tasks from persistent store', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());
      final revokeStore = InMemoryRevokeStore();

      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue('tasks.success');
      await revokeStore.upsertAll([
        RevokeEntry(
          namespace: 'stem',
          taskId: taskId,
          version: generateRevokeVersion(),
          issuedAt: DateTime.now().toUtc(),
          terminate: true,
        ),
      ]);

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-revoked',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      final revokedSignal = Completer<TaskRevokedPayload>();
      final postrunStates = <String>[];
      final subscriptions = <SignalSubscription>[
        StemSignals.taskRevoked.connect((payload, _) {
          if (payload.envelope.id == taskId && !revokedSignal.isCompleted) {
            revokedSignal.complete(payload);
          }
        }),
        StemSignals.taskPostrun.connect((payload, _) {
          if (payload.envelope.id == taskId) {
            postrunStates.add(payload.state.name);
          }
        }),
      ];

      await worker.start();

      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.revoked &&
              event.envelope?.id == taskId,
        ),
      );

      final status = await backend.get(taskId);
      expect(status?.state, TaskState.cancelled);

      await revokedSignal.future.timeout(const Duration(seconds: 2));
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test('shares group limiter keys across task types', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final limiter = _ScenarioRateLimiter((key, attempt) {
        if (key == 'group:acme' && attempt == 2) {
          return const RateLimitDecision(
            allowed: false,
            retryAfter: Duration(milliseconds: 25),
          );
        }
        return const RateLimitDecision(allowed: true);
      });
      final registry = InMemoryTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.group.a',
            options: const TaskOptions(
              groupRateLimit: RateLimit.perSecond(1),
            ),
            entrypoint: (context, args) async => null,
          ),
        )
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.group.b',
            options: const TaskOptions(
              groupRateLimit: RateLimit.perSecond(1),
            ),
            entrypoint: (context, args) async => null,
          ),
        );
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        rateLimiter: limiter,
        consumerName: 'group-limit-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );
      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final firstId = await stem.enqueue(
        'tasks.group.a',
        headers: const {'tenant': 'acme'},
      );
      final secondId = await stem.enqueue(
        'tasks.group.b',
        headers: const {'tenant': 'acme'},
      );

      await _waitFor(
        () =>
            events
                .where((event) => event.type == WorkerEventType.completed)
                .length >=
            2,
        timeout: const Duration(seconds: 3),
      );

      expect((await backend.get(firstId))?.state, TaskState.succeeded);
      expect((await backend.get(secondId))?.state, TaskState.succeeded);
      expect(
        limiter.keys.where((key) => key == 'group:acme').length,
        greaterThanOrEqualTo(2),
      );
      expect(
        events.any(
          (event) =>
              event.type == WorkerEventType.retried &&
              event.data?['groupRateLimited'] == true,
        ),
        isTrue,
      );

      await sub.cancel();
      await worker.shutdown();
      broker.dispose();
    });

    test(
      'group limiter fail-open continues execution on limiter errors',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 20),
        );
        final backend = InMemoryResultBackend();
        final limiter = _ScenarioRateLimiter((key, attempt) {
          throw StateError('limiter unavailable');
        });
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<void>(
              name: 'tasks.group.failopen',
              options: const TaskOptions(
                groupRateLimit: RateLimit.perMinute(10),
              ),
              entrypoint: (context, args) async => null,
            ),
          );
        final worker = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          rateLimiter: limiter,
          consumerName: 'group-fail-open-worker',
          concurrency: 1,
          prefetchMultiplier: 1,
        );

        await worker.start();
        final stem = Stem(broker: broker, registry: registry, backend: backend);
        final taskId = await stem.enqueue(
          'tasks.group.failopen',
          headers: const {'tenant': 'acme'},
        );

        await _waitForTaskState(backend, taskId, TaskState.succeeded);
        expect((await backend.get(taskId))?.state, TaskState.succeeded);

        await worker.shutdown();
        broker.dispose();
      },
    );

    test(
      'group limiter fail-closed requeues while limiter is unavailable',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 20),
        );
        final backend = InMemoryResultBackend();
        final limiter = _ScenarioRateLimiter((key, attempt) {
          throw StateError('limiter unavailable');
        });
        var executed = 0;
        final registry = InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<void>(
              name: 'tasks.group.failclosed',
              options: const TaskOptions(
                groupRateLimit: RateLimit.perMinute(10),
                groupRateLimiterFailureMode: RateLimiterFailureMode.failClosed,
                maxRetries: 5,
              ),
              entrypoint: (context, args) async {
                executed += 1;
                return null;
              },
            ),
          );
        final worker = Worker(
          broker: broker,
          registry: registry,
          backend: backend,
          rateLimiter: limiter,
          consumerName: 'group-fail-closed-worker',
          concurrency: 1,
          prefetchMultiplier: 1,
          retryStrategy: const _FixedRetryStrategy(
            Duration(milliseconds: 120),
          ),
        );

        await worker.start();
        final stem = Stem(broker: broker, registry: registry, backend: backend);
        final taskId = await stem.enqueue(
          'tasks.group.failclosed',
          headers: const {'tenant': 'acme'},
        );

        await _waitForTaskState(backend, taskId, TaskState.retried);
        expect(executed, equals(0));

        await worker.shutdown();
        broker.dispose();
      },
    );

    test('queue pause persists across restarts until resumed', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final revokeStore = InMemoryRevokeStore();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());

      final workerA = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        subscription: RoutingSubscription(
          queues: const ['default', 'priority'],
        ),
        consumerName: 'pause-worker-a',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );
      await workerA.start();

      final pauseReply = await _sendControlCommand(
        broker: broker,
        namespace: workerA.namespace,
        queue: ControlQueueNames.worker(
          workerA.namespace,
          workerA.consumerName!,
        ),
        type: 'queue_pause',
        payload: const {
          'queues': ['default', 'priority'],
        },
      );
      expect(pauseReply.status, equals('ok'));
      await workerA.shutdown();

      final workerB = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        subscription: RoutingSubscription(
          queues: const ['default', 'priority'],
        ),
        consumerName: 'pause-worker-b',
        concurrency: 1,
        prefetchMultiplier: 1,
        revokeStore: revokeStore,
      );
      final events = <WorkerEvent>[];
      final sub = workerB.events.listen(events.add);
      await workerB.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.success');
      await _assertTaskRemainsQueued(backend, taskId);

      final resumeReply = await _sendControlCommand(
        broker: broker,
        namespace: workerB.namespace,
        queue: ControlQueueNames.worker(
          workerB.namespace,
          workerB.consumerName!,
        ),
        type: 'queue_resume',
        payload: const {
          'queues': ['default', 'priority'],
        },
      );
      expect(resumeReply.status, equals('ok'));

      await _waitFor(
        () => events.any(
          (event) =>
              event.type == WorkerEventType.completed &&
              event.envelope?.id == taskId,
        ),
        timeout: const Duration(seconds: 3),
      );
      expect((await backend.get(taskId))?.state, TaskState.succeeded);

      await sub.cancel();
      await workerB.shutdown();
      broker.dispose();
    });

    test('emits control command signals', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = InMemoryTaskRegistry()..register(_SuccessTask());

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'control-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final received = Completer<ControlCommandReceivedPayload>();
      final completed = Completer<ControlCommandCompletedPayload>();
      final subs = <SignalSubscription>[
        StemSignals.onControlCommandReceived((payload, _) {
          if (payload.command.requestId == 'req-ctrl' &&
              !received.isCompleted) {
            received.complete(payload);
          }
        }),
        StemSignals.onControlCommandCompleted((payload, _) {
          if (payload.command.requestId == 'req-ctrl' &&
              !completed.isCompleted) {
            completed.complete(payload);
          }
        }),
      ];

      await worker.start();

      final command = ControlCommandMessage(
        requestId: 'req-ctrl',
        type: 'ping',
        targets: const ['*'],
      );
      final queue = ControlQueueNames.worker(
        worker.namespace,
        worker.consumerName!,
      );
      await broker.publish(command.toEnvelope(queue: queue));

      final receivedPayload = await received.future.timeout(
        const Duration(seconds: 2),
      );
      expect(receivedPayload.command.type, 'ping');

      final completedPayload = await completed.future.timeout(
        const Duration(seconds: 2),
      );
      expect(completedPayload.status, 'ok');
      expect(completedPayload.response?['queue'], worker.primaryQueue);

      for (final sub in subs) {
        sub.cancel();
      }
      await worker.shutdown();
      broker.dispose();
    });
  });
}

class _SuccessTask implements TaskHandler<String> {
  @override
  String get name => 'tasks.success';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    context.heartbeat();
    return 'ok';
  }
}

class _ChordBodyTask implements TaskHandler<int> {
  @override
  String get name => 'tasks.body';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<int> call(TaskContext context, Map<String, Object?> args) async {
    return (args['value']! as num).toInt();
  }
}

class _ChordCallbackTask implements TaskHandler<int> {
  @override
  String get name => 'tasks.chord.callback';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<int> call(TaskContext context, Map<String, Object?> args) async {
    final results = (context.meta['chordResults'] as List?) ?? const [];
    return results
        .map((value) => (value as num?)?.toInt() ?? 0)
        .fold<int>(0, (sum, value) => sum + value);
  }
}

class _AckFailingBroker extends InMemoryBroker {
  _AckFailingBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
        defaultVisibilityTimeout: const Duration(milliseconds: 30),
      );

  int ackAttempts = 0;
  bool failNextAck = true;

  @override
  Future<void> ack(Delivery delivery) async {
    ackAttempts += 1;
    if (failNextAck) {
      failNextAck = false;
      throw StateError('simulated acknowledgement disconnect');
    }
    await super.ack(delivery);
  }
}

class _LeaseLossBroker extends InMemoryBroker {
  _LeaseLossBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
        defaultVisibilityTimeout: const Duration(milliseconds: 80),
      );

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    if (consumerName != 'lease-loss-worker-1') {
      return super.consume(
        subscription,
        prefetch: prefetch,
        consumerGroup: consumerGroup,
        consumerName: consumerName,
      );
    }

    // Model a worker process that stops consuming after receiving its active
    // delivery. The delivery remains leased until the broker's visibility
    // timeout, allowing the replacement worker to receive the redelivery.
    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>(
      onListen: () async {
        try {
          final delivery = await super
              .consume(
                subscription,
                prefetch: prefetch,
                consumerGroup: consumerGroup,
                consumerName: consumerName,
              )
              .first;
          if (!controller.isClosed) {
            controller.add(delivery);
          }
        } on Object catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    throw StateError('simulated lease renewal disconnect');
  }
}

class _BlockingAckBroker extends InMemoryBroker {
  _BlockingAckBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
        defaultVisibilityTimeout: const Duration(milliseconds: 80),
      );

  final Completer<void> ackStarted = Completer<void>();
  final Completer<void> ackCompleted = Completer<void>();
  final Completer<void> _ackRelease = Completer<void>();
  int leaseExtensions = 0;

  @override
  Future<void> ack(Delivery delivery) async {
    if (!ackStarted.isCompleted) {
      ackStarted.complete();
    }
    await _ackRelease.future;
    await super.ack(delivery);
    if (!ackCompleted.isCompleted) {
      ackCompleted.complete();
    }
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    leaseExtensions += 1;
    await super.extendLease(delivery, by);
  }

  void releaseAcknowledgement() {
    if (!_ackRelease.isCompleted) {
      _ackRelease.complete();
    }
  }
}

class _BlockingConsumeBroker extends InMemoryBroker {
  _BlockingConsumeBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
        defaultVisibilityTimeout: const Duration(milliseconds: 80),
      );

  int leaseExtensions = 0;

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    leaseExtensions += 1;
    await super.extendLease(delivery, by);
  }
}

class _BlockingConsumeMiddleware implements Middleware {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  @override
  Future<void> onConsume(
    Delivery delivery,
    Future<void> Function() next,
  ) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await _release.future;
    await next();
  }

  @override
  Future<void> onEnqueue(
    Envelope envelope,
    Future<void> Function() next,
  ) => next();

  @override
  Future<void> onExecute(
    TaskContext context,
    Future<void> Function() next,
  ) => next();

  @override
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  ) async {}

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

class _DelayedTerminalBackend extends InMemoryResultBackend {
  final Completer<void> firstTerminalEntered = Completer<void>();
  final Completer<void> _firstTerminalRelease = Completer<void>();
  int terminalCalls = 0;

  @override
  Future<bool> setTerminalIfAbsent(
    TaskStatus status, {
    Duration? ttl,
  }) async {
    terminalCalls += 1;
    if (terminalCalls == 1) {
      firstTerminalEntered.complete();
      await _firstTerminalRelease.future;
    }
    return super.setTerminalIfAbsent(status, ttl: ttl);
  }

  void releaseFirstTerminal() {
    if (!_firstTerminalRelease.isCompleted) {
      _firstTerminalRelease.complete();
    }
  }
}

class _SequencedSuccessTask implements TaskHandler<String> {
  int calls = 0;

  @override
  String get name => 'tasks.sequenced-success';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    calls += 1;
    return 'result-$calls';
  }
}

class _LeaseLossTask implements TaskHandler<String> {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();
  final Completer<void> _firstRelease = Completer<void>();
  int calls = 0;

  @override
  String get name => 'tasks.lease-loss';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    calls += 1;
    if (calls == 1) {
      firstStarted.complete();
      await _firstRelease.future;
      return 'result-1';
    }
    secondStarted.complete();
    return 'result-2';
  }

  void releaseFirst() {
    if (!_firstRelease.isCompleted) {
      _firstRelease.complete();
    }
  }
}

class _CountingSuccessTask implements TaskHandler<String> {
  _CountingSuccessTask(this.onCall);

  final void Function() onCall;

  @override
  String get name => 'tasks.counting-success';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    onCall();
    return 'ok';
  }
}

class _BlockingSuccessTask implements TaskHandler<String> {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int calls = 0;

  @override
  String get name => 'tasks.blocking-success';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    calls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    await _release.future;
    return 'ok';
  }

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
}

Future<void> _waitForCallbackSuccess(
  ResultBackend backend,
  String taskId, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  return _waitForTaskState(
    backend,
    taskId,
    TaskState.succeeded,
    timeout: timeout,
  );
}

Future<void> _waitForTaskState(
  ResultBackend backend,
  String taskId,
  TaskState expected, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final status = await backend.get(taskId);
    if (status?.state == expected) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Task $taskId did not reach state ${expected.name}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _assertTaskRemainsQueued(
  ResultBackend backend,
  String taskId, {
  Duration holdFor = const Duration(milliseconds: 180),
}) async {
  await _waitFor(() async {
    final status = await backend.get(taskId);
    return status?.state != null;
  });
  final deadline = DateTime.now().add(holdFor);
  while (DateTime.now().isBefore(deadline)) {
    final status = await backend.get(taskId);
    if (status?.state != TaskState.queued) {
      throw StateError(
        'Expected task $taskId to remain queued while paused. '
        'Found ${status?.state}.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<ControlReplyMessage> _sendControlCommand({
  required Broker broker,
  required String namespace,
  required String queue,
  required String type,
  Map<String, Object?> payload = const {},
}) async {
  final requestId = generateEnvelopeId();
  final replyQueue = ControlQueueNames.reply(namespace, requestId);
  final completer = Completer<ControlReplyMessage>();

  late final StreamSubscription<Delivery> subscription;
  subscription = broker
      .consume(
        RoutingSubscription.singleQueue(replyQueue),
        consumerName: 'worker-test-control-$requestId',
      )
      .listen((delivery) async {
        final reply = controlReplyFromEnvelope(delivery.envelope);
        await broker.ack(delivery);
        if (!completer.isCompleted) {
          completer.complete(reply);
        }
      });

  final command = ControlCommandMessage(
    requestId: requestId,
    type: type,
    targets: const ['*'],
    payload: payload,
  );
  await broker.publish(command.toEnvelope(queue: queue));
  try {
    return await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    await subscription.cancel();
  }
}

class _ScenarioRateLimiter implements RateLimiter {
  _ScenarioRateLimiter(this._decision);

  final RateLimitDecision Function(String key, int attempt) _decision;
  final Map<String, int> _attempts = <String, int>{};
  final List<String> keys = <String>[];

  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    final attempt = (_attempts[key] ?? 0) + 1;
    _attempts[key] = attempt;
    keys.add(key);
    return _decision(key, attempt);
  }
}

class _FixedRetryStrategy implements RetryStrategy {
  const _FixedRetryStrategy(this.delay);

  final Duration delay;

  @override
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace) => delay;
}

class _RecordingLogDriver extends LogDriver {
  _RecordingLogDriver() : entries = <LogEntry>[], super('recording');

  final List<LogEntry> entries;

  @override
  Future<void> log(LogEntry entry) async {
    entries.add(entry);
  }
}

class _FlakyTask implements TaskHandler<void> {
  int _attempts = 0;

  @override
  String get name => 'tasks.flaky';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (_attempts == 0) {
      _attempts++;
      throw StateError('first attempt fails');
    }
    await context.progress(1);
  }
}

class _AlwaysFailTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.fail';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 1);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    throw StateError('always fails');
  }
}

class _RetryStormTask implements TaskHandler<void> {
  final Map<int, int> _callsByJob = {};

  int get calls => _callsByJob.values.fold(0, (sum, count) => sum + count);

  @override
  String get name => 'tasks.retry-storm';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final job = args['job']! as int;
    _callsByJob[job] = (_callsByJob[job] ?? 0) + 1;
    throw StateError('retry storm failure for job $job');
  }
}

class _PoisonPayloadTask implements TaskHandler<void> {
  int calls = 0;

  @override
  String get name => 'tasks.poison-payload';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 10);

  @override
  TaskMetadata get metadata => const TaskMetadata(
    argsEncoder: _ThrowingArgsEncoder(),
  );

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls += 1;
  }
}

class _ThrowingArgsEncoder extends TaskPayloadEncoder {
  const _ThrowingArgsEncoder();

  @override
  String get id => 'poison-test';

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) {
    throw const FormatException('payload is intentionally malformed');
  }
}

FutureOr<Object?> _isolateEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  context.heartbeat();
  await context.progress(0.5);
  return (args['value']! as int) * 2;
}

FutureOr<Object?> _hardLimitEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  if (context.attempt == 0) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  return 'done';
}

FutureOr<Object?> _autoscaleEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  return null;
}

FutureOr<Object?> _sleepyEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return null;
}

FutureOr<int> _shutdownRequeueEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  return Isolate.current.hashCode;
}

FutureOr<String> _prefetchShutdownEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return 'completed:${args['index']}';
}

FutureOr<int> _isolateHashEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  return Isolate.current.hashCode;
}
