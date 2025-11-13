import '../core/contracts.dart';
import '../core/stem.dart';
import '../core/task_payload_encoder.dart';
import '../core/unique_task_coordinator.dart';
import '../security/signing.dart';
import '../worker/worker.dart';
import '../control/revoke_store.dart';
import '../control/in_memory_revoke_store.dart';
import '../routing/routing_registry.dart';
import '../routing/routing_config.dart';
import '../backend/encoding_result_backend.dart';
import 'factories.dart';

/// Convenience bootstrap for setting up a Stem runtime with sensible defaults.
class StemApp {
  StemApp._({
    required this.registry,
    required this.broker,
    required this.backend,
    required this.stem,
    required this.worker,
    required List<Future<void> Function()> disposers,
  }) : _disposers = disposers;

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

  final List<Future<void> Function()> _disposers;

  bool _started = false;

  /// Registers an additional task handler with the underlying registry.
  void register(TaskHandler handler) => registry.register(handler);

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

  /// Creates a new Stem application with the provided configuration.
  static Future<StemApp> create({
    Iterable<TaskHandler> tasks = const [],
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
    for (final handler in tasks) {
      taskRegistry.register(handler);
    }

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

    final stem = Stem(
      broker: brokerInstance,
      registry: taskRegistry,
      backend: encodedBackend,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      retryStrategy: retryStrategy,
      middleware: middleware.toList(growable: false),
      routing: routing ?? RoutingRegistry(RoutingConfig.legacy()),
      signer: signer,
      encoderRegistry: payloadEncoders,
    );

    final revoke = revokeStore ?? InMemoryRevokeStore();

    final worker = Worker(
      broker: brokerInstance,
      registry: taskRegistry,
      backend: encodedBackend,
      revokeStore: revoke,
      queue: workerConfig.queue,
      consumerName: workerConfig.consumerName,
      concurrency: workerConfig.concurrency,
      prefetchMultiplier: workerConfig.prefetchMultiplier,
      prefetch: workerConfig.prefetch,
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
    Iterable<TaskHandler> tasks = const [],
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
}
