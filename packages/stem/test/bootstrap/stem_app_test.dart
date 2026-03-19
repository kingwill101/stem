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
        await app.start();

        final taskId = await app.stem.enqueue('test.echo');
        final completed = await app.backend
            .watch(taskId)
            .firstWhere((status) => status.state == TaskState.succeeded)
            .timeout(const Duration(seconds: 1));
        expect(completed.state, TaskState.succeeded);
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
        await app.start();
        final taskId = await app.stem.enqueue('test.from-url');
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
          decode: (payload) =>
              _DemoPayload.fromJson(payload! as Map<String, Object?>),
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
      final workflowRef =
          WorkflowRef<Map<String, Object?>, String>(
            name: 'workflow.ref.flow',
            encodeParams: (params) => params,
          );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [moduleFlow]);
      try {
        final runId = await workflowRef.call(
          const {'name': 'stem'},
        ).startWithApp(workflowApp);
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
        final workflowRef =
            WorkflowRef<Map<String, Object?>, _DemoPayload>(
              name: 'workflow.codec.flow',
              encodeParams: (params) => params,
              decodeResult: _demoPayloadCodec.decode,
            );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          final runId = await workflowRef.call(const {}).startWithApp(
            workflowApp,
          );
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
      'script workflow codecs persist encoded checkpoints and decode typed results',
      () async {
        final script = WorkflowScript<_DemoPayload>(
          name: 'workflow.codec.script',
          resultCodec: _demoPayloadCodec,
          checkpoints: [
            FlowStep.typed<_DemoPayload>(
              name: 'build',
              handler: (_) async => null,
              valueCodec: _demoPayloadCodec,
            ),
            FlowStep.typed<_DemoPayload>(
              name: 'finish',
              handler: (_) async => null,
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
        final workflowRef =
            WorkflowRef<Map<String, Object?>, _DemoPayload>(
              name: 'workflow.codec.script',
              encodeParams: (params) => params,
              decodeResult: _demoPayloadCodec.decode,
            );

        final workflowApp = await StemWorkflowApp.inMemory(scripts: [script]);
        try {
          final runId = await workflowRef.call(const {}).startWithApp(
            workflowApp,
          );
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

class _DemoPayload {
  const _DemoPayload(this.foo);

  factory _DemoPayload.fromJson(Map<String, Object?> json) =>
      _DemoPayload(json['foo']! as String);

  final String foo;
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
