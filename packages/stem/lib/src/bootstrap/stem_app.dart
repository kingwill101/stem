import 'package:stem/src/backend/encoding_result_backend.dart';
import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_client.dart';
import 'package:stem/src/canvas/canvas.dart';
import 'package:stem/src/control/in_memory_revoke_store.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/routing/routing_config.dart';
import 'package:stem/src/routing/routing_registry.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/worker/worker.dart';

/// Convenience bootstrap for setting up a Stem runtime with sensible defaults.
class StemApp {
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
    final taskRegistry = registry ?? SimpleTaskRegistry();
    tasks.forEach(taskRegistry.register);

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
      subscription: workerConfig.subscription,
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
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    return StemApp.create(
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

  /// Creates a Stem app using a shared [StemClient].
  static Future<StemApp> fromClient(
    StemClient client, {
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(),
  }) async {
    tasks.forEach(client.taskRegistry.register);

    final worker = Worker(
      broker: client.broker,
      registry: client.taskRegistry,
      backend: client.backend,
      enqueuer: client.stem,
      rateLimiter: workerConfig.rateLimiter,
      middleware: workerConfig.middleware ?? client.middleware,
      revokeStore: workerConfig.revokeStore,
      uniqueTaskCoordinator:
          workerConfig.uniqueTaskCoordinator ?? client.uniqueTaskCoordinator,
      retryStrategy: workerConfig.retryStrategy ?? client.retryStrategy,
      queue: workerConfig.queue,
      subscription: workerConfig.subscription,
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
      registry: client.taskRegistry,
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
