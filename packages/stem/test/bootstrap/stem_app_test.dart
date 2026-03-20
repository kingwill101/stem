import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'test_store_adapter.dart';

void main() {
  group('StemApp', () {
    test('inMemory executes tasks', () async {
      final handler = FunctionTaskHandler<void>(
        name: 'test.echo',
        entrypoint: (context, args) async => null,
        metadata: const TaskMetadata(idempotent: true),
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        final taskId = await app.enqueue('test.echo');
        final completed = await app.backend
            .watch(taskId)
            .firstWhere((status) => status.state == TaskState.succeeded)
            .timeout(const Duration(seconds: 1));
        expect(completed.state, TaskState.succeeded);
      } finally {
        await app.shutdown();
      }
    });

    test('inMemory lazy-starts on first enqueue', () async {
      final handler = FunctionTaskHandler<String>(
        name: 'test.lazy-start',
        entrypoint: (context, args) async => 'started',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        final taskId = await app.enqueue('test.lazy-start');
        final completed = await app.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 2),
        );
        expect(completed?.value, 'started');
      } finally {
        await app.shutdown();
      }
    });

    test('inMemory exposes task and group status helpers', () async {
      final taskHandler = FunctionTaskHandler<String>(
        name: 'test.status.task',
        entrypoint: (context, args) async => 'status-ok',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(tasks: [taskHandler]);
      try {
        final taskId = await app.enqueue('test.status.task');
        final taskStatus = await app.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 2),
        );
        expect(taskStatus?.value, 'status-ok');
        expect((await app.getTaskStatus(taskId))?.state, TaskState.succeeded);

        final dispatch = await app.canvas.group<String>([
          task('test.status.task'),
        ]);
        try {
          final groupStatus = await _waitForGroupStatus(
            () => app.getGroupStatus(dispatch.groupId),
          );
          expect(groupStatus?.completed, 1);
        } finally {
          await dispatch.dispose();
        }
      } finally {
        await app.shutdown();
      }
    });

    test(
      'inMemory registers module tasks and infers queued subscriptions',
      () async {
        final handler = FunctionTaskHandler<String>(
          name: 'test.module.queue',
          options: const TaskOptions(queue: 'priority'),
          entrypoint: (context, args) async => 'module-ok',
          runInIsolate: false,
        );

        final app = await StemApp.inMemory(
          module: StemModule(tasks: [handler]),
        );
        try {
          expect(app.registry.resolve('test.module.queue'), same(handler));
          expect(app.worker.subscription.queues, ['priority']);

          final taskId = await app.enqueue(
            'test.module.queue',
            enqueueOptions: const TaskEnqueueOptions(queue: 'priority'),
          );
          final completed = await app.waitForTask<String>(
            taskId,
            timeout: const Duration(seconds: 2),
          );
          expect(completed?.value, 'module-ok');
        } finally {
          await app.shutdown();
        }
      },
    );

    test('inMemory infers queued subscriptions from explicit tasks', () async {
      final handler = FunctionTaskHandler<String>(
        name: 'test.explicit.queue',
        options: const TaskOptions(queue: 'priority'),
        entrypoint: (context, args) async => 'explicit-ok',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        expect(app.worker.subscription.queues, ['priority']);

        final taskId = await app.enqueue(
          'test.explicit.queue',
          enqueueOptions: const TaskEnqueueOptions(queue: 'priority'),
        );
        final completed = await app.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 2),
        );
        expect(completed?.value, 'explicit-ok');
      } finally {
        await app.shutdown();
      }
    });

    test('inMemory lazy-starts for canvas dispatch', () async {
      final handler = FunctionTaskHandler<int>(
        name: 'test.canvas.double',
        entrypoint: (context, args) async {
          final value = args['value'] as int? ?? 0;
          return value * 2;
        },
        runInIsolate: false,
      );

      final app = await StemApp.inMemory(tasks: [handler]);
      try {
        final result = await app.canvas.chain<int>([
          task('test.canvas.double', args: {'value': 21}),
        ]);

        expect(result.isCompleted, isTrue);
        expect(result.value, 42);
      } finally {
        await app.shutdown();
      }
    });

    test('StemApp exposes task registration helpers', () async {
      final directHandler = FunctionTaskHandler<String>(
        name: 'test.register.direct',
        entrypoint: (context, args) async => 'direct-ok',
        runInIsolate: false,
      );
      final moduleHandler = FunctionTaskHandler<String>(
        name: 'test.register.module',
        entrypoint: (context, args) async => 'module-ok',
        runInIsolate: false,
      );
      final extraHandler = FunctionTaskHandler<String>(
        name: 'test.register.extra',
        entrypoint: (context, args) async => 'extra-ok',
        runInIsolate: false,
      );

      final app = await StemApp.inMemory();
      try {
        app
          ..registerTask(directHandler)
          ..registerModule(StemModule(tasks: [moduleHandler]))
          ..registerModules([
            StemModule(tasks: [extraHandler]),
          ]);

        final directTaskId = await app.enqueue('test.register.direct');
        final directResult = await app.waitForTask<String>(
          directTaskId,
          timeout: const Duration(seconds: 2),
        );
        expect(directResult?.value, 'direct-ok');

        final moduleTaskId = await app.enqueue('test.register.module');
        final moduleResult = await app.waitForTask<String>(
          moduleTaskId,
          timeout: const Duration(seconds: 2),
        );
        expect(moduleResult?.value, 'module-ok');

        final extraTaskId = await app.enqueue('test.register.extra');
        final extraResult = await app.waitForTask<String>(
          extraTaskId,
          timeout: const Duration(seconds: 2),
        );
        expect(extraResult?.value, 'extra-ok');
      } finally {
        await app.shutdown();
      }
    });

    test('inMemory applies worker config overrides', () async {
      final handler = FunctionTaskHandler<void>(
        name: 'test.worker-config',
        entrypoint: (context, args) async => null,
        metadata: const TaskMetadata(idempotent: true),
      );
      final rateLimiter = _TestRateLimiter();
      final middleware = _TestMiddleware();
      final revokeStore = InMemoryRevokeStore();
      final uniqueTaskCoordinator = UniqueTaskCoordinator(
        lockStore: InMemoryLockStore(),
      );
      final retryStrategy = _TestRetryStrategy();
      final subscription = RoutingSubscription(
        queues: ['alpha', 'beta'],
        broadcastChannels: ['broadcast'],
      );
      const autoscale = WorkerAutoscaleConfig(
        enabled: true,
        minConcurrency: 2,
        maxConcurrency: 4,
      );
      const lifecycle = WorkerLifecycleConfig(
        installSignalHandlers: false,
        maxTasksPerIsolate: 5,
      );
      final observability = ObservabilityConfig(
        namespace: 'observed',
        heartbeatInterval: const Duration(seconds: 3),
      );
      final signer = PayloadSigner(const SigningConfig.disabled());

      final app = await StemApp.inMemory(
        tasks: [handler],
        workerConfig: StemWorkerConfig(
          queue: 'priority',
          consumerName: 'custom-worker',
          concurrency: 4,
          prefetchMultiplier: 3,
          prefetch: 7,
          rateLimiter: rateLimiter,
          middleware: [middleware],
          revokeStore: revokeStore,
          uniqueTaskCoordinator: uniqueTaskCoordinator,
          retryStrategy: retryStrategy,
          subscription: subscription,
          heartbeatInterval: const Duration(seconds: 9),
          workerHeartbeatInterval: const Duration(seconds: 7),
          heartbeatTransport: const NoopHeartbeatTransport(),
          heartbeatNamespace: 'heartbeat',
          autoscale: autoscale,
          lifecycle: lifecycle,
          observability: observability,
          signer: signer,
        ),
      );
      try {
        final worker = app.worker;
        expect(worker.queue, 'priority');
        expect(worker.consumerName, 'custom-worker');
        expect(worker.concurrency, 4);
        expect(worker.prefetchMultiplier, 3);
        expect(worker.prefetch, 7);
        expect(worker.rateLimiter, same(rateLimiter));
        expect(worker.middleware, hasLength(1));
        expect(worker.middleware.first, same(middleware));
        expect(worker.revokeStore, same(revokeStore));
        expect(worker.uniqueTaskCoordinator, same(uniqueTaskCoordinator));
        expect(worker.retryStrategy, same(retryStrategy));
        expect(worker.subscription.queues, ['alpha', 'beta']);
        expect(worker.subscription.broadcastChannels, ['broadcast']);
        expect(worker.heartbeatInterval, const Duration(seconds: 9));
        expect(
          worker.workerHeartbeatInterval,
          observability.heartbeatInterval,
        );
        expect(worker.heartbeatTransport, isA<NoopHeartbeatTransport>());
        expect(worker.namespace, 'observed');
        expect(worker.autoscaleConfig.enabled, isTrue);
        expect(worker.autoscaleConfig.minConcurrency, 2);
        expect(worker.autoscaleConfig.maxConcurrency, 4);
        expect(worker.lifecycleConfig.installSignalHandlers, isFalse);
        expect(worker.lifecycleConfig.maxTasksPerIsolate, 5);
        expect(worker.signer, same(signer));

        final canvas = app.canvas;
        expect(canvas.broker, same(app.broker));
        expect(canvas.backend, same(app.backend));
        expect(canvas.registry, same(app.registry));
        expect(canvas.payloadEncoders, same(app.stem.payloadEncoders));
      } finally {
        await app.shutdown();
      }
    });

    test('fromUrl resolves adapter-backed broker/backend', () async {
      final handler = FunctionTaskHandler<void>(
        name: 'test.from-url',
        entrypoint: (context, args) async => null,
      );
      final adapter = TestStoreAdapter(
        scheme: 'test',
        adapterName: 'bootstrap-test-adapter',
        broker: StemBrokerFactory(create: () async => InMemoryBroker()),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
      );

      final app = await StemApp.fromUrl(
        'test://localhost',
        adapters: [adapter],
        tasks: [handler],
      );
      try {
        final taskId = await app.enqueue('test.from-url');
        final completed = await app.backend
            .watch(taskId)
            .firstWhere((status) => status.state == TaskState.succeeded)
            .timeout(const Duration(seconds: 1));
        expect(completed.state, TaskState.succeeded);
      } finally {
        await app.shutdown();
      }
    });

    test(
      'fromUrl auto-wires unique/revoke stores and disposes them on shutdown',
      () async {
        final createdLockStore = InMemoryLockStore();
        final createdRevokeStore = InMemoryRevokeStore();
        var lockDisposed = false;
        var revokeDisposed = false;
        final adapter = TestStoreAdapter(
          scheme: 'test',
          adapterName: 'bootstrap-test-adapter',
          broker: StemBrokerFactory(create: () async => InMemoryBroker()),
          backend: StemBackendFactory(
            create: () async => InMemoryResultBackend(),
          ),
          lock: LockStoreFactory(
            create: () async => createdLockStore,
            dispose: (store) async => lockDisposed = true,
          ),
          revoke: RevokeStoreFactory(
            create: () async => createdRevokeStore,
            dispose: (store) async => revokeDisposed = true,
          ),
        );

        final app = await StemApp.fromUrl(
          'test://localhost',
          adapters: [adapter],
          uniqueTasks: true,
          requireRevokeStore: true,
        );
        try {
          expect(app.worker.uniqueTaskCoordinator, isNotNull);
          expect(app.worker.revokeStore, same(createdRevokeStore));
        } finally {
          await app.shutdown();
        }

        expect(lockDisposed, isTrue);
        expect(revokeDisposed, isTrue);
      },
    );

    test(
      'fromUrl disposes auto-wired stores when app bootstrap fails',
      () async {
        final createdLockStore = InMemoryLockStore();
        final createdRevokeStore = InMemoryRevokeStore();
        var lockDisposed = false;
        var revokeDisposed = false;
        final adapter = TestStoreAdapter(
          scheme: 'test',
          adapterName: 'bootstrap-test-adapter',
          broker: StemBrokerFactory(
            create: () async => throw StateError('broker bootstrap failure'),
          ),
          backend: StemBackendFactory(
            create: () async => InMemoryResultBackend(),
          ),
          lock: LockStoreFactory(
            create: () async => createdLockStore,
            dispose: (store) async => lockDisposed = true,
          ),
          revoke: RevokeStoreFactory(
            create: () async => createdRevokeStore,
            dispose: (store) async => revokeDisposed = true,
          ),
        );

        await expectLater(
          () => StemApp.fromUrl(
            'test://localhost',
            adapters: [adapter],
            uniqueTasks: true,
            requireRevokeStore: true,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('broker bootstrap failure'),
            ),
          ),
        );

        expect(lockDisposed, isTrue);
        expect(revokeDisposed, isTrue);
      },
    );
  });

  group('StemWorkflowApp', () {
    test('inMemory runs workflow to completion', () async {
      final flow = Flow(
        name: 'workflow.demo',
        build: (builder) {
          builder.step('hello', (ctx) async => 'hello world');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.demo');
        final run = await workflowApp
            .waitForCompletion<String>(
              runId,
              timeout: const Duration(seconds: 1),
            )
            .timeout(const Duration(seconds: 2));

        expect(run, isNotNull);
        expect(run!.status, WorkflowStatus.completed);
        expect(run.value, 'hello world');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('waitForCompletion decodes custom types on success', () async {
      final flow = Flow<Map<String, Object?>>(
        name: 'workflow.typed',
        build: (builder) {
          builder.step('payload', (ctx) async => {'foo': 'bar'});
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.typed');
        final run = await workflowApp.waitForCompletion<_DemoPayload>(
          runId,
          decodeJson: _DemoPayload.fromJson,
        );

        expect(run, isNotNull);
        expect(run!.value, isA<_DemoPayload>());
        expect(run.value!.foo, 'bar');
        expect(run.state.result, {'foo': 'bar'});
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'waitForCompletion decodes versioned custom types on success',
      () async {
        final flow = Flow<Map<String, Object?>>(
          name: 'workflow.typed.versioned',
          build: (builder) {
            builder.step(
              'payload',
              (ctx) async => {
                PayloadCodec.versionKey: 2,
                'foo': 'bar',
              },
            );
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowApp.startWorkflow(
            'workflow.typed.versioned',
          );
          final run = await workflowApp.waitForCompletion<_DemoPayload>(
            runId,
            decodeVersionedJson: _DemoPayload.fromVersionedJson,
          );

          expect(run, isNotNull);
          expect(run!.value, isA<_DemoPayload>());
          expect(run.value!.foo, 'bar-v2');
          expect(run.state.result, {
            PayloadCodec.versionKey: 2,
            'foo': 'bar',
          });
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('startWorkflowJson encodes DTO params without a manual map', () async {
      final flow = Flow<String>(
        name: 'workflow.json.start',
        build: (builder) {
          builder.step(
            'payload',
            (ctx) async => ctx.requiredParam<String>('foo'),
          );
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflowJson(
          'workflow.json.start',
          const _DemoPayload('bar'),
        );
        final run = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(runId, isNotEmpty);
        expect(run?.requiredValue(), 'bar');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'startWorkflowVersionedJson encodes DTO params with a persisted '
      'schema version',
      () async {
        final flow = Flow<String>(
          name: 'workflow.versioned.json.start',
          build: (builder) {
            builder.step(
              'payload',
              (ctx) async => ctx.requiredParam<String>('foo'),
            );
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowApp.startWorkflowVersionedJson(
            'workflow.versioned.json.start',
            const _DemoPayload('bar'),
            version: 2,
          );
          final runState = await workflowApp.getRun(runId);
          final run = await workflowApp.waitForCompletion<String>(
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(runId, isNotEmpty);
          expect(runState?.params, containsPair(PayloadCodec.versionKey, 2));
          expect(runState?.params, containsPair('foo', 'bar'));
          expect(run?.requiredValue(), 'bar');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'emitJson resumes runs with DTO payloads without a manual map',
      () async {
        const demoPayloadCodec = PayloadCodec<_DemoPayload>.json(
          decode: _DemoPayload.fromJson,
        );
        final flow = Flow<String?>(
          name: 'workflow.json.emit',
          build: (builder) {
            builder.step<String?>(
              'wait',
              (ctx) async {
                final resume = ctx.takeResumeValue<_DemoPayload>(
                  codec: demoPayloadCodec,
                );
                if (resume == null) {
                  ctx.awaitEvent('workflow.json.emit.topic');
                  return null;
                }
                return resume.foo;
              },
            );
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowApp.startWorkflow('workflow.json.emit');
          await workflowApp.executeRun(runId);

          await workflowApp.emitJson(
            'workflow.json.emit.topic',
            const _DemoPayload('baz'),
          );

          final run = await workflowApp.waitForCompletion<String>(
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(runId, isNotEmpty);
          expect(run?.requiredValue(), 'baz');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'emitVersionedJson resumes runs with versioned DTO payloads',
      () async {
        const demoPayloadCodec = PayloadCodec<_DemoPayload>.json(
          decode: _DemoPayload.fromJson,
        );
        final flow = Flow<String?>(
          name: 'workflow.versioned.json.emit',
          build: (builder) {
            builder.step<String?>(
              'wait',
              (ctx) async {
                final resume = ctx.takeResumeValue<_DemoPayload>(
                  codec: demoPayloadCodec,
                );
                if (resume == null) {
                  ctx.awaitEvent('workflow.versioned.json.emit.topic');
                  return null;
                }
                return resume.foo;
              },
            );
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowApp.startWorkflow(
            'workflow.versioned.json.emit',
          );
          await workflowApp.executeRun(runId);

          await workflowApp.emitVersionedJson(
            'workflow.versioned.json.emit.topic',
            const _DemoPayload('qux'),
            version: 2,
          );

          final run = await workflowApp.waitForCompletion<String>(
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(runId, isNotEmpty);
          expect(run?.requiredValue(), 'qux');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'waitForCompletion does not decode when workflow is cancelled',
      () async {
        final flow = Flow(
          name: 'workflow.cancelled',
          build: (builder) {
            builder.step('noop', (ctx) async => 'done');
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          var decodeInvocations = 0;
          final runId = await workflowApp.startWorkflow('workflow.cancelled');
          await workflowApp.runtime.cancelWorkflow(runId);

          final run = await workflowApp.waitForCompletion<Object?>(
            runId,
            decode: (payload) {
              decodeInvocations += 1;
              return payload;
            },
          );

          expect(run, isNotNull);
          expect(run!.status, WorkflowStatus.cancelled);
          expect(run.value, isNull);
          expect(decodeInvocations, 0);
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('waitForCompletion returns non-terminal state on timeout', () async {
      final flow = Flow(
        name: 'workflow.timeout',
        build: (builder) {
          builder.step('sleep', (ctx) async {
            final resume = ctx.takeResumeData();
            if (resume != true) {
              ctx.sleep(const Duration(seconds: 5));
              return null;
            }
            return 'done';
          });
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.timeout');
        final result = await workflowApp.waitForCompletion(
          runId,
          timeout: const Duration(milliseconds: 100),
        );

        expect(result, isNotNull);
        expect(result!.timedOut, isTrue);
        expect(result.status, WorkflowStatus.suspended);
        expect(result.value, isNull);
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('fromUrl runs workflow to completion', () async {
      final flow = Flow<String>(
        name: 'workflow.from-url',
        build: (builder) {
          builder.step('hello', (ctx) async => 'from-url');
        },
      );
      final adapter = TestStoreAdapter(
        scheme: 'test',
        adapterName: 'bootstrap-test-adapter',
        broker: StemBrokerFactory(create: () async => InMemoryBroker()),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
        workflow: WorkflowStoreFactory(
          create: () async => InMemoryWorkflowStore(),
        ),
      );

      final workflowApp = await StemWorkflowApp.fromUrl(
        'test://localhost',
        adapters: [adapter],
        flows: [flow],
      );
      try {
        final runId = await workflowApp.startWorkflow('workflow.from-url');
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'from-url');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('fromUrl registers provided tasks', () async {
      final helperTask = FunctionTaskHandler<void>(
        name: 'workflow.task.helper',
        entrypoint: (context, args) async => null,
        runInIsolate: false,
      );
      final adapter = TestStoreAdapter(
        scheme: 'test',
        adapterName: 'bootstrap-test-adapter',
        broker: StemBrokerFactory(create: () async => InMemoryBroker()),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
        workflow: WorkflowStoreFactory(
          create: () async => InMemoryWorkflowStore(),
        ),
      );

      final workflowApp = await StemWorkflowApp.fromUrl(
        'test://localhost',
        adapters: [adapter],
        tasks: [helperTask],
      );
      try {
        expect(
          workflowApp.app.registry.resolve('workflow.task.helper'),
          same(helperTask),
        );
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('inMemory registers module tasks and workflows', () async {
      final helperTask = FunctionTaskHandler<String>(
        name: 'workflow.module.helper',
        entrypoint: (context, args) async => 'ok',
        runInIsolate: false,
      );
      final moduleFlow = Flow<String>(
        name: 'workflow.module.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'from-module');
        },
      );
      final module = StemModule(flows: [moduleFlow], tasks: [helperTask]);

      final workflowApp = await StemWorkflowApp.inMemory(module: module);
      try {
        expect(
          workflowApp.app.registry.resolve('workflow.module.helper'),
          same(helperTask),
        );

        final runId = await workflowApp.startWorkflow('workflow.module.flow');
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'from-module');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'inMemory infers worker subscription from module task queues',
      () async {
        final helperTask = FunctionTaskHandler<String>(
          name: 'workflow.module.queue-helper',
          entrypoint: (context, args) async => 'queued-ok',
          runInIsolate: false,
        );
        final helperDefinition = TaskDefinition.noArgs<String>(
          name: 'workflow.module.queue-helper',
        );
        final workflowApp = await StemWorkflowApp.inMemory(
          module: StemModule(tasks: [helperTask]),
        );
        try {
          expect(
            workflowApp.app.worker.subscription.queues,
            unorderedEquals(['workflow', 'default']),
          );

          await workflowApp.start();
          final result = await helperDefinition.enqueueAndWait(
            workflowApp,
            timeout: const Duration(seconds: 2),
          );
          expect(result?.value, 'queued-ok');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'explicit workflow subscription overrides inferred module queues',
      () async {
        final helperTask = FunctionTaskHandler<String>(
          name: 'workflow.module.explicit-subscription',
          entrypoint: (context, args) async => 'ignored',
          runInIsolate: false,
        );
        final workflowApp = await StemWorkflowApp.inMemory(
          module: StemModule(tasks: [helperTask]),
          workerConfig: StemWorkerConfig(
            queue: 'workflow',
            subscription: RoutingSubscription.singleQueue('workflow'),
          ),
        );
        try {
          expect(workflowApp.app.worker.subscription.queues, ['workflow']);
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('workflow refs start and decode runs through app helpers', () async {
      final moduleFlow = Flow<String>(
        name: 'workflow.ref.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'workflow.ref.flow',
        encodeParams: (params) => params,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [moduleFlow]);
      try {
        final runId = await workflowRef
            .call(
              const {'name': 'stem'},
            )
            .start(workflowApp);
        final result = await workflowRef.waitFor(
          workflowApp,
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello stem');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes run detail helper', () async {
      final flow = Flow<String>(
        name: 'workflow.detail.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'detail-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.detail.helper');
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'detail-ok');

        final detail = await workflowApp.viewRunDetail(runId);
        expect(detail, isNotNull);
        expect(detail!.run.runId, equals(runId));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes workflow manifest helper', () async {
      final flow = Flow<String>(
        name: 'workflow.manifest.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'manifest-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final manifest = workflowApp.workflowManifest();
        final entry = manifest.singleWhere(
          (item) => item.name == 'workflow.manifest.helper',
        );
        expect(entry.kind, equals(WorkflowDefinitionKind.flow));
        expect(entry.steps.single.name, equals('hello'));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'StemWorkflowApp registers module definitions after bootstrap',
      () async {
        final taskHandler = FunctionTaskHandler<String>.inline(
          name: 'workflow.module.task',
          entrypoint: (context, args) async => 'module-task-ok',
        );
        final flow = Flow<String>(
          name: 'workflow.module.flow',
          build: (builder) {
            builder.step('hello', (ctx) async => 'module-flow-ok');
          },
        );
        final module = StemModule(flows: [flow], tasks: [taskHandler]);

        final workflowApp = await StemWorkflowApp.inMemory();
        try {
          workflowApp.registerModule(module);

          expect(
            workflowApp.app.registry.resolve('workflow.module.task'),
            isNotNull,
          );
          expect(
            workflowApp.runtime.registry.lookup('workflow.module.flow'),
            isNotNull,
          );

          final runId = await workflowApp.startWorkflow('workflow.module.flow');
          final workflowResult = await workflowApp.waitForCompletion<String>(
            runId,
            timeout: const Duration(seconds: 2),
          );
          expect(workflowResult?.value, equals('module-flow-ok'));
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('StemWorkflowApp exposes workflow registration helper', () async {
      final flow = Flow<String>(
        name: 'workflow.register.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'register-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory();
      try {
        workflowApp.registerWorkflow(flow.definition);

        final runId = await workflowApp.startWorkflow(
          'workflow.register.helper',
        );
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, equals('register-ok'));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'StemWorkflowApp exposes flow and script registration helpers',
      () async {
        final flow = Flow<String>(
          name: 'workflow.register.flow.helper',
          build: (builder) {
            builder.step('hello', (ctx) async => 'flow-register-ok');
          },
        );
        final script = WorkflowScript<String>(
          name: 'workflow.register.script.helper',
          run: (script) => script.step<String>(
            'hello',
            (step) async => 'script-register-ok',
          ),
        );

        final workflowApp = await StemWorkflowApp.inMemory();
        try {
          workflowApp
            ..registerFlow(flow)
            ..registerScript(script);

          final flowRunId = await workflowApp.startWorkflow(
            'workflow.register.flow.helper',
          );
          final flowResult = await workflowApp.waitForCompletion<String>(
            flowRunId,
            timeout: const Duration(seconds: 2),
          );
          expect(flowResult?.value, equals('flow-register-ok'));

          final scriptRunId = await workflowApp.startWorkflow(
            'workflow.register.script.helper',
          );
          final scriptResult = await workflowApp.waitForCompletion<String>(
            scriptRunId,
            timeout: const Duration(seconds: 2),
          );
          expect(scriptResult?.value, equals('script-register-ok'));
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'StemWorkflowApp exposes bulk flow and script registration helpers',
      () async {
        final flow = Flow<String>(
          name: 'workflow.register.flows.helper',
          build: (builder) {
            builder.step('hello', (ctx) async => 'flows-register-ok');
          },
        );
        final script = WorkflowScript<String>(
          name: 'workflow.register.scripts.helper',
          run: (script) => script.step<String>(
            'hello',
            (step) async => 'scripts-register-ok',
          ),
        );

        final workflowApp = await StemWorkflowApp.inMemory();
        try {
          workflowApp
            ..registerFlows([flow])
            ..registerScripts([script]);

          final flowRunId = await workflowApp.startWorkflow(
            'workflow.register.flows.helper',
          );
          final flowResult = await workflowApp.waitForCompletion<String>(
            flowRunId,
            timeout: const Duration(seconds: 2),
          );
          expect(flowResult?.value, equals('flows-register-ok'));

          final scriptRunId = await workflowApp.startWorkflow(
            'workflow.register.scripts.helper',
          );
          final scriptResult = await workflowApp.waitForCompletion<String>(
            scriptRunId,
            timeout: const Duration(seconds: 2),
          );
          expect(scriptResult?.value, equals('scripts-register-ok'));
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('StemWorkflowApp exposes bulk workflow registration helper', () async {
      final definition = WorkflowDefinition<String>.flow(
        name: 'workflow.register.definitions.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'definitions-register-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory();
      try {
        workflowApp.registerWorkflows([definition]);

        final runId = await workflowApp.startWorkflow(
          'workflow.register.definitions.helper',
        );
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, equals('definitions-register-ok'));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes run view helpers', () async {
      final flow = Flow<String>(
        name: 'workflow.views.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'views-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.views.helper');
        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'views-ok');

        final runView = await workflowApp.viewRun(runId);
        expect(runView, isNotNull);
        expect(runView!.runId, equals(runId));

        final checkpoints = await workflowApp.viewCheckpoints(runId);
        expect(checkpoints, hasLength(1));
        expect(checkpoints.single.baseCheckpointName, equals('hello'));

        final runViews = await workflowApp.listRunViews(
          workflow: 'workflow.views.helper',
        );
        expect(runViews.map((view) => view.runId), contains(runId));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes executeRun helper', () async {
      final flow = Flow<String>(
        name: 'workflow.execute.helper',
        build: (builder) {
          builder.step('hello', (ctx) async => 'execute-ok');
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow(
          'workflow.execute.helper',
        );
        await workflowApp.executeRun(runId);

        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, 'execute-ok');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes rewind helper', () async {
      final iterations = <int>[];
      final flow = Flow<String>(
        name: 'workflow.rewind.helper',
        build: (builder) {
          builder
            ..step('repeat', (ctx) async {
              iterations.add(ctx.iteration);
              return 'iteration-${ctx.iteration}';
            }, autoVersion: true)
            ..step('tail', (ctx) async => ctx.previousResult! as String);
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow('workflow.rewind.helper');
        await workflowApp.executeRun(runId);

        await workflowApp.rewindToCheckpoint(runId, 'repeat');
        await workflowApp.executeRun(runId);

        final checkpoints = await workflowApp.viewCheckpoints(runId);
        expect(
          checkpoints.map((checkpoint) => checkpoint.checkpointName),
          containsAll(['repeat#0', 'tail']),
        );
        expect(iterations, equals([0, 0]));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes watcher helper', () async {
      final script = WorkflowScript<String>(
        name: 'workflow.watchers.helper',
        run: (script) async {
          final payload = await script.step<String>('wait', (step) async {
            await step.awaitEvent(
              'watchers.helper.topic',
              deadline: DateTime.now().add(const Duration(minutes: 5)),
            );
            return 'waiting';
          });
          return payload;
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(scripts: [script]);
      try {
        final runId = await workflowApp.startWorkflow(
          'workflow.watchers.helper',
        );
        await workflowApp.executeRun(runId);

        final watchers = await workflowApp.listWatchers(
          'watchers.helper.topic',
        );
        expect(watchers, hasLength(1));
        expect(watchers.single.runId, equals(runId));
        expect(watchers.single.stepName, equals('wait'));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('StemWorkflowApp exposes due-run resume helper', () async {
      var iterations = 0;
      final flow = Flow<String>(
        name: 'workflow.resume.due.helper',
        build: (builder) {
          builder.step('loop', (ctx) async {
            iterations += 1;
            if (iterations == 1) {
              ctx.sleep(const Duration(milliseconds: 25));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        final runId = await workflowApp.startWorkflow(
          'workflow.resume.due.helper',
        );
        await workflowApp.executeRun(runId);

        await Future<void>.delayed(const Duration(milliseconds: 35));
        final resumed = await workflowApp.resumeDueRuns(DateTime.now());
        expect(resumed, contains(runId));

        for (final id in resumed) {
          await workflowApp.executeRun(id);
        }

        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.value, equals('resumed'));
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'workflow codecs persist encoded checkpoints and decode typed results',
      () async {
        final flow = Flow<_DemoPayload>(
          name: 'workflow.codec.flow',
          resultCodec: _demoPayloadCodec,
          build: (builder) {
            builder
              ..step<_DemoPayload>(
                'build',
                (ctx) async => const _DemoPayload('bar'),
                valueCodec: _demoPayloadCodec,
              )
              ..step<_DemoPayload>(
                'finish',
                (ctx) async {
                  final previous = ctx.previousResult! as _DemoPayload;
                  return _DemoPayload('${previous.foo}-done');
                },
                valueCodec: _demoPayloadCodec,
              );
          },
        );
        final workflowRef = flow.ref0();

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowRef.call().start(workflowApp);
          final result = await workflowRef.waitFor(
            workflowApp,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(result, isNotNull);
          expect(result!.value?.foo, 'bar-done');
          expect(result.state.result, {'foo': 'bar-done'});
          expect(
            await workflowApp.store.readStep<Map<String, Object?>>(
              runId,
              'build',
            ),
            {'foo': 'bar'},
          );
          expect(
            await workflowApp.store.readStep<Map<String, Object?>>(
              runId,
              'finish',
            ),
            {'foo': 'bar-done'},
          );
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test(
      'script workflow codecs persist encoded checkpoints '
      'and decode typed results',
      () async {
        final script = WorkflowScript<_DemoPayload>(
          name: 'workflow.codec.script',
          resultCodec: _demoPayloadCodec,
          checkpoints: [
            WorkflowCheckpoint.typed<_DemoPayload>(
              name: 'build',
              valueCodec: _demoPayloadCodec,
            ),
            WorkflowCheckpoint.typed<_DemoPayload>(
              name: 'finish',
              valueCodec: _demoPayloadCodec,
            ),
          ],
          run: (script) async {
            final built = await script.step<_DemoPayload>(
              'build',
              (ctx) async => const _DemoPayload('bar'),
            );
            return script.step<_DemoPayload>(
              'finish',
              (ctx) async => _DemoPayload('${built.foo}-done'),
            );
          },
        );
        final workflowRef = script.ref0();

        final workflowApp = await StemWorkflowApp.inMemory(scripts: [script]);
        try {
          final runId = await workflowRef.call().start(workflowApp);
          final result = await workflowRef.waitFor(
            workflowApp,
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(result, isNotNull);
          expect(result!.value?.foo, 'bar-done');
          expect(result.state.result, {'foo': 'bar-done'});
          expect(
            await workflowApp.store.readStep<Map<String, Object?>>(
              runId,
              'build',
            ),
            {'foo': 'bar'},
          );
          expect(
            await workflowApp.store.readStep<Map<String, Object?>>(
              runId,
              'finish',
            ),
            {'foo': 'bar-done'},
          );
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('fromUrl shuts down app when workflow bootstrap fails', () async {
      final createdLockStore = InMemoryLockStore();
      final createdRevokeStore = InMemoryRevokeStore();
      var lockDisposed = false;
      var revokeDisposed = false;
      final adapter = TestStoreAdapter(
        scheme: 'test',
        adapterName: 'bootstrap-test-adapter',
        broker: StemBrokerFactory(create: () async => InMemoryBroker()),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
        workflow: WorkflowStoreFactory(
          create: () async => InMemoryWorkflowStore(),
        ),
        lock: LockStoreFactory(
          create: () async => createdLockStore,
          dispose: (store) async => lockDisposed = true,
        ),
        revoke: RevokeStoreFactory(
          create: () async => createdRevokeStore,
          dispose: (store) async => revokeDisposed = true,
        ),
      );

      await expectLater(
        () => StemWorkflowApp.fromUrl(
          'test://localhost',
          adapters: [adapter],
          uniqueTasks: true,
          requireRevokeStore: true,
          eventBusFactory: WorkflowEventBusFactory(
            create: (store) async =>
                throw StateError('event bus bootstrap failure'),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('event bus bootstrap failure'),
          ),
        ),
      );

      expect(lockDisposed, isTrue);
      expect(revokeDisposed, isTrue);
    });
  });
}

Future<GroupStatus?> _waitForGroupStatus(
  Future<GroupStatus?> Function() lookup, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await lookup();
    if (status != null && status.completed == status.expected) {
      return status;
    }
    await Future<void>.delayed(pollInterval);
  }
  return lookup();
}

class _DemoPayload {
  const _DemoPayload(this.foo);

  factory _DemoPayload.fromJson(Map<String, Object?> json) =>
      _DemoPayload(json['foo']! as String);

  factory _DemoPayload.fromVersionedJson(
    Map<String, Object?> json,
    int version,
  ) => _DemoPayload('${json['foo']! as String}-v$version');

  final String foo;

  Map<String, Object?> toJson() => {'foo': foo};
}

const _demoPayloadCodec = PayloadCodec<_DemoPayload>(
  encode: _encodeDemoPayload,
  decode: _decodeDemoPayload,
);

Object? _encodeDemoPayload(_DemoPayload value) => {'foo': value.foo};

_DemoPayload _decodeDemoPayload(Object? payload) {
  return _DemoPayload.fromJson(Map<String, Object?>.from(payload! as Map));
}

class _TestRateLimiter implements RateLimiter {
  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    return const RateLimitDecision(allowed: true);
  }
}

class _TestRetryStrategy implements RetryStrategy {
  @override
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace) =>
      const Duration(milliseconds: 50);
}

class _TestMiddleware implements Middleware {
  @override
  Future<void> onConsume(Delivery delivery, Future<void> Function() next) =>
      next();

  @override
  Future<void> onEnqueue(Envelope envelope, Future<void> Function() next) =>
      next();

  @override
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  ) async {}

  @override
  Future<void> onExecute(TaskContext context, Future<void> Function() next) =>
      next();
}
