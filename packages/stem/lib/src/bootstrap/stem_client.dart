import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_app.dart';
import 'package:stem/src/bootstrap/stem_module.dart';
import 'package:stem/src/bootstrap/stem_stack.dart';
import 'package:stem/src/bootstrap/workflow_app.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/task_result.dart';
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
abstract class StemClient implements TaskResultCaller {
  /// Creates a client using the provided factories and defaults.
  static Future<StemClient> create({
    StemModule? module,
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
      module: module,
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
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig defaultWorkerConfig = const StemWorkerConfig(),
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    return create(
      module: module,
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

  /// Creates a client from a single backend URL plus adapter wiring.
  ///
  /// This resolves broker/backend factories via [StemStack.fromUrl] so callers
  /// can avoid manual factory wiring for common Redis/Postgres/SQLite setups.
  static Future<StemClient> fromUrl(
    String url, {
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? taskRegistry,
    WorkflowRegistry? workflowRegistry,
    Iterable<StemStoreAdapter> adapters = const [],
    StemStoreOverrides overrides = const StemStoreOverrides(),
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
  }) {
    final stack = StemStack.fromUrl(
      url,
      adapters: adapters,
      overrides: overrides,
    );
    return create(
      module: module,
      tasks: tasks,
      taskRegistry: taskRegistry,
      workflowRegistry: workflowRegistry,
      broker: stack.broker,
      backend: stack.backend,
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

  /// Underlying broker used by the client.
  Broker get broker;

  /// Result backend used by workers and producers.
  ResultBackend get backend;

  /// Shared task registry for handlers.
  TaskRegistry get taskRegistry;

  /// Shared workflow registry for workflow definitions.
  WorkflowRegistry get workflowRegistry;

  /// Optional default bundle registered into this client.
  StemModule? get module;

  /// Enqueue facade for producers.
  Stem get stem;

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

  /// Waits for a task result by task id using the client's shared backend.
  @override
  Future<TaskResult<TResult>?> waitForTask<TResult extends Object?>(
    String taskId, {
    Duration? timeout,
    TResult Function(Object? payload)? decode,
  }) {
    return stem.waitForTask(taskId, timeout: timeout, decode: decode);
  }

  /// Waits for a task result using a typed [definition] for decoding.
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
    final bundledTasks = module?.tasks ?? const <TaskHandler<Object?>>[];
    final allTasks = [...bundledTasks, ...tasks];
    registerModuleTaskHandlers(taskRegistry, allTasks);
    final inferredSubscription =
        config.subscription ??
        module?.inferTaskWorkerSubscription(
          defaultQueue: config.queue,
          additionalTasks: tasks,
        ) ??
        (() {
          final tempModule = StemModule(tasks: tasks);
          return tempModule.inferTaskWorkerSubscription(
            defaultQueue: config.queue,
          );
        })();
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
      subscription: inferredSubscription,
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
    StemModule? module,
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
    final effectiveModule = module ?? this.module;
    return StemWorkflowApp.fromClient(
      client: this,
      module: effectiveModule,
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
    StemModule? module,
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig? workerConfig,
  }) {
    final effectiveModule = module ?? this.module;
    return StemApp.fromClient(
      this,
      module: effectiveModule,
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
    required this.module,
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
    StemModule? module,
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
    final bundledTasks = module?.tasks ?? const <TaskHandler<Object?>>[];
    final allTasks = [...bundledTasks, ...tasks];
    final registry = taskRegistry ?? InMemoryTaskRegistry();
    registerModuleTaskHandlers(registry, allTasks);
    final workflows = workflowRegistry ?? InMemoryWorkflowRegistry();
    module?.registerInto(workflows: workflows);

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
      module: module,
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
  final StemModule? module;

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
