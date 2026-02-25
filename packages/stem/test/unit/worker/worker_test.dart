import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Worker', () {
    test('executes task and records success', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-1',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      final events = <WorkerEvent>[];
      final sub = worker.events.listen(events.add);

      await worker.start();

      final stem = Stem(broker: broker, registry: registry, backend: backend);
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

    test('dispatches chord callback when body completes', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()..register(_FlakyTask());
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

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
      final registry = SimpleTaskRegistry()..register(_FlakyTask());
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
      final registry = SimpleTaskRegistry()..register(_FlakyTask());

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
      final registry = SimpleTaskRegistry()..register(_AlwaysFailTask());
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

    test('executes handler inside isolate when entrypoint provided', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
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
      final registry = SimpleTaskRegistry()
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

    test('skips revoked tasks from persistent store', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());
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
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.group.a',
            options: const TaskOptions(
              groupRateLimit: '1/s',
            ),
            entrypoint: (context, args) async => null,
          ),
        )
        ..register(
          FunctionTaskHandler<void>(
            name: 'tasks.group.b',
            options: const TaskOptions(
              groupRateLimit: '1/s',
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
        final registry = SimpleTaskRegistry()
          ..register(
            FunctionTaskHandler<void>(
              name: 'tasks.group.failopen',
              options: const TaskOptions(
                groupRateLimit: '10/m',
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
        final registry = SimpleTaskRegistry()
          ..register(
            FunctionTaskHandler<void>(
              name: 'tasks.group.failclosed',
              options: const TaskOptions(
                groupRateLimit: '10/m',
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

      final workerA = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
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
          'queues': ['default'],
        },
      );
      expect(pauseReply.status, equals('ok'));
      await workerA.shutdown();

      final workerB = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
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
          'queues': ['default'],
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
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

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

FutureOr<int> _isolateHashEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  return Isolate.current.hashCode;
}
