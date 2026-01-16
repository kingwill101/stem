import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_app.dart';
import 'package:stem/src/bootstrap/workflow_app.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/routing/routing_config.dart';
import 'package:stem/src/routing/routing_registry.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/worker/worker.dart';
import 'package:stem/src/workflow/core/flow.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_script.dart';
import 'package:stem/src/workflow/runtime/workflow_introspection.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';

/// Shared entrypoint that owns broker/backend configuration for Stem runtimes.
abstract class StemClient {
  /// Creates a client using the provided factories and defaults.
  static Future<StemClient> create({
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? taskRegistry,
    WorkflowRegistry? workflowRegistry,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    RoutingRegistry? routing,
    RetryStrategy? retryStrategy,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    StemWorkerConfig defaultWorkerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    return _DefaultStemClient.create(
      tasks: tasks,
      taskRegistry: taskRegistry,
      workflowRegistry: workflowRegistry,
      broker: broker,
      backend: backend,
      routing: routing,
      retryStrategy: retryStrategy,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      middleware: middleware,
      signer: signer,
      defaultWorkerConfig: defaultWorkerConfig,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }

  /// Creates an in-memory client using in-memory broker/backend.
  static Future<StemClient> inMemory({
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig defaultWorkerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    return create(
      tasks: tasks,
      broker: StemBrokerFactory.inMemory(),
      backend: StemBackendFactory.inMemory(),
      defaultWorkerConfig: defaultWorkerConfig,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }

  /// Underlying broker used by the client.
  Broker get broker;

  /// Result backend used by workers and producers.
  ResultBackend get backend;

  /// Shared task registry for handlers.
  TaskRegistry get taskRegistry;

  /// Shared workflow registry for workflow definitions.
  WorkflowRegistry get workflowRegistry;

  /// Enqueue facade for producers.
  Stem get stem;

  /// Payload encoder registry used for task args/results.
  TaskPayloadEncoderRegistry get encoderRegistry;

  /// Routing registry used for enqueue decisions.
  RoutingRegistry get routing;

  /// Retry strategy applied by the worker runtime.
  RetryStrategy get retryStrategy;

  /// Unique task coordinator used by workers.
  UniqueTaskCoordinator? get uniqueTaskCoordinator;

  /// Default middleware applied to workers/enqueue.
  List<Middleware> get middleware;

  /// Optional signer used to validate payloads.
  PayloadSigner? get signer;

  /// Default worker configuration applied when creating workers.
  StemWorkerConfig get defaultWorkerConfig;

  /// Creates a worker using the shared broker/backend/registry.
  Future<Worker> createWorker({
    StemWorkerConfig? workerConfig,
    Iterable<TaskHandler<Object?>> tasks = const [],
  }) async {
    final config = workerConfig ?? defaultWorkerConfig;
    tasks.forEach(taskRegistry.register);
    return Worker(
      broker: broker,
      registry: taskRegistry,
      backend: backend,
      enqueuer: stem,
      rateLimiter: config.rateLimiter,
      middleware: config.middleware ?? middleware,
      revokeStore: config.revokeStore,
      uniqueTaskCoordinator:
          config.uniqueTaskCoordinator ?? uniqueTaskCoordinator,
      retryStrategy: config.retryStrategy ?? retryStrategy,
      queue: config.queue,
      subscription: config.subscription,
      consumerName: config.consumerName,
      concurrency: config.concurrency,
      prefetchMultiplier: config.prefetchMultiplier,
      prefetch: config.prefetch,
      heartbeatInterval: config.heartbeatInterval,
      workerHeartbeatInterval: config.workerHeartbeatInterval,
      heartbeatTransport: config.heartbeatTransport,
      heartbeatNamespace: config.heartbeatNamespace,
      autoscale: config.autoscale,
      lifecycle: config.lifecycle,
      observability: config.observability,
      signer: config.signer ?? signer,
      encoderRegistry: encoderRegistry,
    );
  }

  /// Creates a workflow app using the shared client configuration.
  Future<StemWorkflowApp> createWorkflowApp({
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    WorkflowStoreFactory? storeFactory,
    WorkflowEventBusFactory? eventBusFactory,
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowIntrospectionSink? introspectionSink,
  }) {
    return StemWorkflowApp.fromClient(
      client: this,
      workflows: workflows,
      flows: flows,
      scripts: scripts,
      storeFactory: storeFactory,
      eventBusFactory: eventBusFactory,
      workerConfig: workerConfig,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
      introspectionSink: introspectionSink,
    );
  }

  /// Creates a StemApp wrapper using the shared client configuration.
  Future<StemApp> createApp({
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig? workerConfig,
  }) {
    return StemApp.fromClient(
      this,
      tasks: tasks,
      workerConfig: workerConfig ?? defaultWorkerConfig,
    );
  }

  /// Releases resources held by the client.
  Future<void> close();
}

class _DefaultStemClient extends StemClient {
  _DefaultStemClient({
    required this.broker,
    required this.backend,
    required this.taskRegistry,
    required this.workflowRegistry,
    required this.stem,
    required this.encoderRegistry,
    required this.routing,
    required this.retryStrategy,
    required this.uniqueTaskCoordinator,
    required List<Middleware> middleware,
    required this.signer,
    required this.defaultWorkerConfig,
    required this.disposeBroker,
    required this.disposeBackend,
  }) : middleware = List.unmodifiable(middleware);

  static Future<StemClient> create({
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? taskRegistry,
    WorkflowRegistry? workflowRegistry,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    RoutingRegistry? routing,
    RetryStrategy? retryStrategy,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    StemWorkerConfig defaultWorkerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    final registry = taskRegistry ?? SimpleTaskRegistry();
    tasks.forEach(registry.register);
    final workflows = workflowRegistry ?? InMemoryWorkflowRegistry();

    final brokerFactory = broker ?? StemBrokerFactory.inMemory();
    final backendFactory = backend ?? StemBackendFactory.inMemory();
    final brokerInstance = await brokerFactory.create();
    final backendInstance = await backendFactory.create();

    final middlewareList = List<Middleware>.from(middleware);

    final stem = Stem(
      broker: brokerInstance,
      registry: registry,
      backend: backendInstance,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      retryStrategy: retryStrategy,
      middleware: middlewareList,
      routing: routing ?? RoutingRegistry(RoutingConfig.legacy()),
      signer: signer,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );

    return _DefaultStemClient(
      broker: brokerInstance,
      backend: backendInstance,
      taskRegistry: registry,
      workflowRegistry: workflows,
      stem: stem,
      encoderRegistry: stem.payloadEncoders,
      routing: stem.routing,
      retryStrategy: stem.retryStrategy,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      middleware: middlewareList,
      signer: signer,
      defaultWorkerConfig: defaultWorkerConfig,
      disposeBroker: () async => brokerFactory.dispose(brokerInstance),
      disposeBackend: () async => backendFactory.dispose(backendInstance),
    );
  }

  @override
  final Broker broker;

  @override
  final ResultBackend backend;

  @override
  final TaskRegistry taskRegistry;

  @override
  final WorkflowRegistry workflowRegistry;

  @override
  final Stem stem;

  @override
  final TaskPayloadEncoderRegistry encoderRegistry;

  @override
  final RoutingRegistry routing;

  @override
  final RetryStrategy retryStrategy;

  @override
  final UniqueTaskCoordinator? uniqueTaskCoordinator;

  @override
  final List<Middleware> middleware;

  @override
  final PayloadSigner? signer;

  @override
  final StemWorkerConfig defaultWorkerConfig;

  final Future<void> Function() disposeBroker;
  final Future<void> Function() disposeBackend;

  @override
  Future<void> close() async {
    await disposeBroker();
    await disposeBackend();
  }
}
