import 'package:stem/src/backend/encoding_result_backend.dart';
import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_client.dart';
import 'package:stem/src/bootstrap/stem_module.dart';
import 'package:stem/src/bootstrap/stem_stack.dart';
import 'package:stem/src/canvas/canvas.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/task_result.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/routing/routing_config.dart';
import 'package:stem/src/routing/routing_registry.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/worker/worker.dart';
import 'package:stem_memory/stem_memory.dart' show InMemoryRevokeStore;

/// Convenience bootstrap for setting up a Stem runtime with sensible defaults.
abstract interface class StemTaskApp implements TaskResultCaller {}

/// Convenience bootstrap for setting up a Stem runtime with sensible defaults.
class StemApp implements StemTaskApp {
  StemApp._({
    required this.registry,
    required this.broker,
    required this.backend,
    required this.stem,
    required this.worker,
    required List<Future<void> Function()> disposers,
  }) : _disposers = disposers {
    canvas = Canvas(
      broker: broker,
      backend: backend,
      registry: registry,
      encoderRegistry: stem.payloadEncoders,
    );
  }

  /// Task registry containing all registered handlers.
  final TaskRegistry registry;

  /// Active broker instance used by the helper.
  final Broker broker;

  /// Optional result backend used by the helper.
  final ResultBackend backend;

  /// Stem facade used to enqueue tasks.
  final Stem stem;

  /// Worker managed by the helper.
  final Worker worker;

  /// Canvas facade used for chains, groups, and chords.
  late final Canvas canvas;

  final List<Future<void> Function()> _disposers;

  bool _started = false;

  /// Registers an additional task handler with the underlying registry.
  void register(TaskHandler<Object?> handler) => registry.register(handler);

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return stem.enqueue(
      name,
      args: args,
      headers: headers,
      options: options,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return stem.enqueueCall(call, enqueueOptions: enqueueOptions);
  }

  @override
  Future<TaskResult<TResult>?> waitForTask<TResult extends Object?>(
    String taskId, {
    Duration? timeout,
    TResult Function(Object? payload)? decode,
  }) {
    return stem.waitForTask(taskId, timeout: timeout, decode: decode);
  }

  @override
  Future<TaskResult<TResult>?> waitForTaskDefinition<
    TArgs,
    TResult extends Object?
  >(
    String taskId,
    TaskDefinition<TArgs, TResult> definition, {
    Duration? timeout,
  }) {
    return stem.waitForTaskDefinition(taskId, definition, timeout: timeout);
  }

  void _insertAutoDisposers(
    List<Future<void> Function()> autoDisposers,
  ) {
    if (autoDisposers.isEmpty) return;
    final insertionIndex = _disposers.length >= 2
        ? _disposers.length - 2
        : _disposers.length;
    _disposers.insertAll(insertionIndex, autoDisposers);
  }

  /// Starts the managed worker if it is not already running.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await worker.start();
  }

  /// Shuts down the worker and disposes any managed resources.
  Future<void> shutdown() async {
    for (final disposer in _disposers) {
      await disposer();
    }
    _started = false;
  }

  /// Alias for [shutdown].
  Future<void> close() => shutdown();

  /// Creates a new Stem application with the provided configuration.
  static Future<StemApp> create({
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? registry,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
    RevokeStore? revokeStore,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    RetryStrategy? retryStrategy,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    final bundledTasks = module?.tasks ?? const <TaskHandler<Object?>>[];
    final allTasks = [...bundledTasks, ...tasks];
    final taskRegistry = registry ?? InMemoryTaskRegistry();
    registerModuleTaskHandlers(taskRegistry, allTasks);

    final brokerFactory = broker ?? StemBrokerFactory.inMemory();
    final backendFactory = backend ?? StemBackendFactory.inMemory();
    final brokerInstance = await brokerFactory.create();
    final backendInstance = await backendFactory.create();

    final payloadEncoders = ensureTaskPayloadEncoderRegistry(
      encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );

    final encodedBackend = withTaskPayloadEncoder(
      backendInstance,
      payloadEncoders,
    );

    final resolvedMiddleware = middleware.toList(growable: false);
    final stem = Stem(
      broker: brokerInstance,
      registry: taskRegistry,
      backend: encodedBackend,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      retryStrategy: retryStrategy,
      middleware: resolvedMiddleware,
      routing: routing ?? RoutingRegistry(RoutingConfig.legacy()),
      signer: signer,
      encoderRegistry: payloadEncoders,
    );

    final revoke =
        workerConfig.revokeStore ?? revokeStore ?? InMemoryRevokeStore();
    final workerMiddleware = workerConfig.middleware ?? resolvedMiddleware;
    final workerRetryStrategy = workerConfig.retryStrategy ?? retryStrategy;
    final workerUniqueTaskCoordinator =
        workerConfig.uniqueTaskCoordinator ?? uniqueTaskCoordinator;
    final workerSigner = workerConfig.signer ?? signer;
    final inferredSubscription =
        workerConfig.subscription ??
        module?.inferTaskWorkerSubscription(
          defaultQueue: workerConfig.queue,
          additionalTasks: tasks,
        );

    final worker = Worker(
      broker: brokerInstance,
      registry: taskRegistry,
      backend: encodedBackend,
      rateLimiter: workerConfig.rateLimiter,
      middleware: workerMiddleware,
      revokeStore: revoke,
      uniqueTaskCoordinator: workerUniqueTaskCoordinator,
      retryStrategy: workerRetryStrategy,
      queue: workerConfig.queue,
      subscription: inferredSubscription,
      consumerName: workerConfig.consumerName,
      concurrency: workerConfig.concurrency,
      prefetchMultiplier: workerConfig.prefetchMultiplier,
      prefetch: workerConfig.prefetch,
      heartbeatInterval: workerConfig.heartbeatInterval,
      workerHeartbeatInterval: workerConfig.workerHeartbeatInterval,
      heartbeatTransport: workerConfig.heartbeatTransport,
      heartbeatNamespace: workerConfig.heartbeatNamespace,
      autoscale: workerConfig.autoscale,
      lifecycle: workerConfig.lifecycle,
      observability: workerConfig.observability,
      signer: workerSigner,
      encoderRegistry: payloadEncoders,
    );

    final disposers = <Future<void> Function()>[
      () async {
        await worker.shutdown();
      },
      () async {
        await backendFactory.dispose(backendInstance);
      },
      () async {
        await brokerFactory.dispose(brokerInstance);
      },
    ];

    return StemApp._(
      registry: taskRegistry,
      broker: brokerInstance,
      backend: encodedBackend,
      stem: stem,
      worker: worker,
      disposers: disposers,
    );
  }

  /// Creates an in-memory Stem application (broker + result backend).
  static Future<StemApp> inMemory({
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    return StemApp.create(
      module: module,
      tasks: tasks,
      broker: StemBrokerFactory.inMemory(),
      backend: StemBackendFactory.inMemory(),
      workerConfig: workerConfig,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }

  /// Creates an app from a single backend URL plus adapter wiring.
  ///
  /// This helper resolves broker/backend factories via [StemStack.fromUrl] and
  /// can optionally auto-wire revoke and unique-task coordination stores.
  static Future<StemApp> fromUrl(
    String url, {
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? registry,
    Iterable<StemStoreAdapter> adapters = const [],
    StemStoreOverrides overrides = const StemStoreOverrides(),
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
    RevokeStore? revokeStore,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    bool uniqueTasks = false,
    Duration uniqueTaskDefaultTtl = const Duration(minutes: 5),
    String uniqueTaskNamespace = 'stem:unique',
    bool requireRevokeStore = false,
    RetryStrategy? retryStrategy,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
    StemStack? stack,
  }) async {
    final needsUniqueLockStore =
        uniqueTasks &&
        uniqueTaskCoordinator == null &&
        workerConfig.uniqueTaskCoordinator == null;
    final needsRevokeStore =
        requireRevokeStore &&
        revokeStore == null &&
        workerConfig.revokeStore == null;

    final resolvedStack =
        stack ??
        StemStack.fromUrl(
          url,
          adapters: adapters,
          overrides: overrides,
          uniqueTasks: needsUniqueLockStore,
          requireRevokeStore: needsRevokeStore,
        );

    final autoDisposers = <Future<void> Function()>[];

    var resolvedUniqueTaskCoordinator =
        uniqueTaskCoordinator ?? workerConfig.uniqueTaskCoordinator;
    if (needsUniqueLockStore) {
      final lockFactory = resolvedStack.lockStore;
      if (lockFactory == null) {
        throw StateError(
          'Unique task coordination requested but lock store factory missing.',
        );
      }
      final lockStore = await lockFactory.create();
      resolvedUniqueTaskCoordinator = UniqueTaskCoordinator(
        lockStore: lockStore,
        defaultTtl: uniqueTaskDefaultTtl,
        namespace: uniqueTaskNamespace,
      );
      autoDisposers.add(() async => lockFactory.dispose(lockStore));
    }

    var resolvedRevokeStore = revokeStore ?? workerConfig.revokeStore;
    if (needsRevokeStore) {
      final revokeFactory = resolvedStack.revokeStore;
      if (revokeFactory == null) {
        throw StateError('Revoke store required but no revoke factory found.');
      }
      final createdRevokeStore = await revokeFactory.create();
      resolvedRevokeStore = createdRevokeStore;
      autoDisposers.add(() async => revokeFactory.dispose(createdRevokeStore));
    }

    try {
      final app = await create(
        module: module,
        tasks: tasks,
        registry: registry,
        broker: resolvedStack.broker,
        backend: resolvedStack.backend,
        workerConfig: workerConfig,
        revokeStore: resolvedRevokeStore,
        uniqueTaskCoordinator: resolvedUniqueTaskCoordinator,
        retryStrategy: retryStrategy,
        middleware: middleware,
        signer: signer,
        routing: routing,
        encoderRegistry: encoderRegistry,
        resultEncoder: resultEncoder,
        argsEncoder: argsEncoder,
        additionalEncoders: additionalEncoders,
      );

      // Dispose auto-provisioned lock/revoke stores after worker shutdown and
      // before backend/broker factories are disposed.
      app._insertAutoDisposers(autoDisposers);

      return app;
    } on Object catch (error, stackTrace) {
      // If app creation fails, release any auto-provisioned stores now to avoid
      // leaking startup resources.
      for (final disposer in autoDisposers.reversed) {
        try {
          await disposer();
        } on Object {
          // Keep the original startup error as the primary failure.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Creates a Stem app using a shared [StemClient].
  static Future<StemApp> fromClient(
    StemClient client, {
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
  }) async {
    final bundledTasks = module?.tasks ?? const <TaskHandler<Object?>>[];
    final allTasks = [...bundledTasks, ...tasks];
    final taskRegistry = client.taskRegistry;
    registerModuleTaskHandlers(taskRegistry, allTasks);
    final inferredSubscription =
        workerConfig.subscription ??
        module?.inferTaskWorkerSubscription(
          defaultQueue: workerConfig.queue,
          additionalTasks: tasks,
        );

    final worker = Worker(
      broker: client.broker,
      registry: taskRegistry,
      backend: client.backend,
      enqueuer: client.stem,
      rateLimiter: workerConfig.rateLimiter,
      middleware: workerConfig.middleware ?? client.middleware,
      revokeStore: workerConfig.revokeStore,
      uniqueTaskCoordinator:
          workerConfig.uniqueTaskCoordinator ?? client.uniqueTaskCoordinator,
      retryStrategy: workerConfig.retryStrategy ?? client.retryStrategy,
      queue: workerConfig.queue,
      subscription: inferredSubscription,
      consumerName: workerConfig.consumerName,
      concurrency: workerConfig.concurrency,
      prefetchMultiplier: workerConfig.prefetchMultiplier,
      prefetch: workerConfig.prefetch,
      heartbeatInterval: workerConfig.heartbeatInterval,
      workerHeartbeatInterval: workerConfig.workerHeartbeatInterval,
      heartbeatTransport: workerConfig.heartbeatTransport,
      heartbeatNamespace: workerConfig.heartbeatNamespace,
      autoscale: workerConfig.autoscale,
      lifecycle: workerConfig.lifecycle,
      observability: workerConfig.observability,
      signer: workerConfig.signer ?? client.signer,
      encoderRegistry: client.encoderRegistry,
    );

    return StemApp._(
      registry: taskRegistry,
      broker: client.broker,
      backend: client.backend,
      stem: client.stem,
      worker: worker,
      disposers: [
        () async {
          await worker.shutdown();
        },
      ],
    );
  }
}
