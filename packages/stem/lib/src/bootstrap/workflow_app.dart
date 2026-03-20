import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_app.dart';
import 'package:stem/src/bootstrap/stem_client.dart';
import 'package:stem/src/bootstrap/stem_module.dart';
import 'package:stem/src/bootstrap/stem_stack.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/contracts.dart'
    show
        GroupStatus,
        TaskCall,
        TaskDefinition,
        TaskEnqueueOptions,
        TaskHandler,
        TaskOptions,
        TaskStatus;
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/task_result.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/workflow/core/event_bus.dart';
import 'package:stem/src/workflow/core/flow.dart';
import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
import 'package:stem/src/workflow/core/workflow_script.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/runtime/workflow_introspection.dart';
import 'package:stem/src/workflow/runtime/workflow_manifest.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';
import 'package:stem/src/workflow/runtime/workflow_runtime.dart';
import 'package:stem/src/workflow/runtime/workflow_views.dart';

/// Helper that bootstraps a workflow runtime on top of [StemApp].
///
/// This wrapper wires together broker/backend infrastructure, registers flows,
/// and exposes convenience helpers for scheduling and observing workflow runs
/// without having to manage [WorkflowRuntime] directly.
class StemWorkflowApp
    implements WorkflowCaller, WorkflowEventEmitter, StemTaskApp {
  StemWorkflowApp._({
    required this.app,
    required this.runtime,
    required this.store,
    required this.eventBus,
    required Future<void> Function() disposeStore,
    required Future<void> Function() disposeBus,
  }) : _disposeStore = disposeStore,
       _disposeBus = disposeBus;

  /// Underlying Stem app used for broker/worker coordination.
  final StemApp app;

  /// Workflow runtime responsible for executing workflow runs.
  final WorkflowRuntime runtime;

  /// Store backing workflow run persistence.
  final WorkflowStore store;

  /// Event bus used to deliver workflow events.
  final EventBus eventBus;

  final Future<void> Function() _disposeStore;
  final Future<void> Function() _disposeBus;

  bool _started = false;

  /// Starts the workflow runtime and the underlying Stem worker.
  ///
  /// Subsequent calls are ignored, so it is safe to call before every
  /// scheduling operation.
  ///
  /// Example:
  /// ```dart
  /// final app = await StemWorkflowApp.inMemory();
  /// await app.start();
  /// ```
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await runtime.start();
    await app.start();
  }

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return app.enqueue(
      name,
      args: args,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return app.enqueueCall(call, enqueueOptions: enqueueOptions);
  }

  @override
  Future<TaskStatus?> getTaskStatus(String taskId) {
    return app.getTaskStatus(taskId);
  }

  @override
  Future<GroupStatus?> getGroupStatus(String groupId) {
    return app.getGroupStatus(groupId);
  }

  @override
  Future<TaskResult<TResult>?> waitForTask<TResult extends Object?>(
    String taskId, {
    Duration? timeout,
    TResult Function(Object? payload)? decode,
  }) {
    return app.waitForTask(taskId, timeout: timeout, decode: decode);
  }

  @override
  Future<TaskResult<TResult>?>
  waitForTaskDefinition<TArgs, TResult extends Object?>(
    String taskId,
    TaskDefinition<TArgs, TResult> definition, {
    Duration? timeout,
  }) {
    return app.waitForTaskDefinition(taskId, definition, timeout: timeout);
  }

  /// Schedules a workflow run.
  ///
  /// Lazily starts the runtime on the first invocation so simple examples do
  /// not need to call [start] manually.
  ///
  /// Example:
  /// ```dart
  /// final app = await StemWorkflowApp.inMemory();
  /// final runId = await app.startWorkflow(
  ///   'exampleWorkflow',
  ///   params: {'key': 'value'},
  /// );
  /// print('Workflow started with ID: $runId');
  /// ```
  Future<String> startWorkflow(
    String name, {
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,

    /// Optional policy that enforces automatic run cancellation.
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    if (!_started) {
      return start().then(
        (_) => runtime.startWorkflow(
          name,
          params: params,
          parentRunId: parentRunId,
          ttl: ttl,
          cancellationPolicy: cancellationPolicy,
        ),
      );
    }
    return runtime.startWorkflow(
      name,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Schedules a workflow run from a typed [WorkflowRef].
  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    if (!_started) {
      return start().then(
        (_) => runtime.startWorkflowRef(
          definition,
          params,
          parentRunId: parentRunId,
          ttl: ttl,
          cancellationPolicy: cancellationPolicy,
        ),
      );
    }
    return runtime.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  /// Schedules a workflow run from a prebuilt [WorkflowStartCall].
  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return startWorkflowRef(
      call.definition,
      call.params,
      parentRunId: call.parentRunId,
      ttl: call.ttl,
      cancellationPolicy: call.cancellationPolicy,
    );
  }

  /// Emits a typed event to resume runs waiting on [topic].
  ///
  /// This is a convenience wrapper over [WorkflowRuntime.emitValue].
  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) {
    return runtime.emitValue(topic, value, codec: codec);
  }

  /// Emits a typed event through a [WorkflowEventRef].
  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    return runtime.emitEvent(event, value);
  }

  /// Returns the current [RunState] of a workflow run, or `null` if not found.
  ///
  /// Example:
  /// ```dart
  /// final runState = await app.getRun('runId123');
  /// if (runState != null) {
  ///   print('Workflow state: ${runState.status}');
  /// } else {
  ///   print('Run not found.');
  /// }
  /// ```
  Future<RunState?> getRun(String runId) => store.get(runId);

  /// Returns the normalized run view for [runId], or `null` if not found.
  Future<WorkflowRunView?> viewRun(String runId) {
    return runtime.viewRun(runId);
  }

  /// Returns persisted checkpoint views for [runId].
  Future<List<WorkflowCheckpointView>> viewCheckpoints(String runId) {
    return runtime.viewCheckpoints(runId);
  }

  /// Returns the combined run + checkpoint detail view for [runId].
  ///
  /// This is a convenience wrapper over [WorkflowRuntime.viewRunDetail] so
  /// callers do not need to reach through [runtime] for common inspection.
  Future<WorkflowRunDetailView?> viewRunDetail(String runId) {
    return runtime.viewRunDetail(runId);
  }

  /// Returns normalized workflow run views filtered by workflow/status.
  Future<List<WorkflowRunView>> listRunViews({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) {
    return runtime.listRunViews(
      workflow: workflow,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  /// Returns the manifest entries for workflows registered with this app.
  List<WorkflowManifestEntry> workflowManifest() {
    return runtime.workflowManifest();
  }

  /// Executes the workflow run identified by [runId].
  ///
  /// This is a convenience wrapper over [WorkflowRuntime.executeRun] for
  /// examples and application code that need direct run driving without
  /// reaching through [runtime].
  Future<void> executeRun(String runId) {
    return runtime.executeRun(runId);
  }

  /// Polls the workflow store until the run reaches a terminal state.
  ///
  /// When the workflow completes successfully the persisted result is surfaced
  /// via [WorkflowResult.value], optionally decoding through [decode]. Failed,
  /// cancelled, or timed-out waits return the original [RunState] metadata with
  /// `value == null` so callers can inspect errors or suspension details.
  ///
  /// Example:
  /// ```dart
  /// final result = await app.waitForCompletion<String>('runId123');
  /// if (result != null && result.value != null) {
  ///   print('Workflow completed with result: ${result.value}');
  /// } else {
  ///   print('Workflow did not complete successfully.');
  /// }
  /// ```
  Future<WorkflowResult<T>?> waitForCompletion<T extends Object?>(
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
    T Function(Object? payload)? decode,
  }) async {
    final startedAt = stemNow();
    while (true) {
      final state = await store.get(runId);
      if (state == null) {
        return null;
      }
      if (state.isTerminal) {
        return _buildResult(state, decode, timedOut: false);
      }
      if (timeout != null && stemNow().difference(startedAt) >= timeout) {
        return _buildResult(state, decode, timedOut: true);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Waits for [runId] using the decoding rules from a [WorkflowRef].
  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return waitForCompletion<TResult>(
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
      decode: definition.decode,
    );
  }

  WorkflowResult<T> _buildResult<T extends Object?>(
    RunState state,
    T Function(Object? payload)? decode, {
    required bool timedOut,
  }) {
    final value = state.status == WorkflowStatus.completed
        ? _decodeResult(state.result, decode)
        : null;
    return WorkflowResult<T>(
      runId: state.id,
      status: state.status,
      state: state,
      value: value,
      rawResult: state.result,
      timedOut: timedOut && !state.isTerminal,
    );
  }

  T? _decodeResult<T extends Object?>(
    Object? payload,
    T Function(Object? payload)? decode,
  ) {
    if (decode != null) {
      return decode(payload);
    }
    return payload as T?;
  }

  /// Stops the runtime, worker, and disposes associated resources.
  ///
  /// After shutdown the instance can be restarted by calling [start] again.
  ///
  /// Example:
  /// ```dart
  /// await app.shutdown();
  /// print('App shutdown complete.');
  /// ```
  Future<void> shutdown() async {
    await runtime.dispose();
    await app.shutdown();
    await _disposeBus();
    await _disposeStore();
    _started = false;
  }

  /// Alias for [shutdown].
  Future<void> close() => shutdown();

  /// Creates a workflow app with custom backends and factories.
  ///
  /// Useful for wiring Redis/Postgres adapters or sharing an existing
  /// [StemApp] instance with job processors. When [module] or [tasks] are
  /// provided and [StemWorkerConfig.subscription] is omitted, the helper
  /// infers a worker subscription that includes the workflow queue plus the
  /// default queues declared on those task handlers.
  ///
  /// Example:
  /// ```dart
  /// final app = await StemWorkflowApp.create(
  ///   workflows: [exampleWorkflow],
  ///   broker: customBroker,
  ///   backend: customBackend,
  /// );
  /// ```
  static Future<StemWorkflowApp> create({
    StemModule? module,
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemApp? stemApp,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    WorkflowStoreFactory? storeFactory,
    WorkflowEventBusFactory? eventBusFactory,
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowRegistry? workflowRegistry,
    WorkflowIntrospectionSink? introspectionSink,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    final effectiveModule = module ?? stemApp?.module;
    final moduleTasks =
        effectiveModule?.tasks ?? const <TaskHandler<Object?>>[];
    final moduleWorkflowDefinitions =
        effectiveModule?.workflowDefinitions ?? const <WorkflowDefinition>[];
    final resolvedWorkerConfig = _resolveWorkflowWorkerConfig(
      workerConfig,
      module: effectiveModule,
      tasks: tasks,
    );
    final appInstance =
        stemApp ??
        await StemApp.create(
          broker: broker ?? StemBrokerFactory.inMemory(),
          backend: backend ?? StemBackendFactory.inMemory(),
          workerConfig: resolvedWorkerConfig,
          encoderRegistry: encoderRegistry,
          resultEncoder: resultEncoder,
          argsEncoder: argsEncoder,
          additionalEncoders: additionalEncoders,
        );
    if (stemApp != null) {
      _validateReusableStemApp(
        appInstance,
        resolvedWorkerConfig,
      );
    }

    final storeFactoryInstance =
        storeFactory ?? WorkflowStoreFactory.inMemory();
    final store = await storeFactoryInstance.create();
    final busFactory = eventBusFactory ?? WorkflowEventBusFactory.inMemory();
    final eventBus = await busFactory.create(store);

    final runtime = WorkflowRuntime(
      stem: appInstance.stem,
      store: store,
      eventBus: eventBus,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
      queue: resolvedWorkerConfig.queue,
      registry: workflowRegistry,
      introspectionSink: introspectionSink,
    );

    registerModuleTaskHandlers(
      appInstance.registry,
      [...moduleTasks, ...tasks],
    );
    appInstance.register(runtime.workflowRunnerHandler());

    [
      ...moduleWorkflowDefinitions,
      ...workflows,
      ...flows.map((flow) => flow.definition),
      ...scripts.map((script) => script.definition),
    ].forEach(runtime.registerWorkflow);

    return StemWorkflowApp._(
      app: appInstance,
      runtime: runtime,
      store: store,
      eventBus: eventBus,
      disposeStore: () async => storeFactoryInstance.dispose(store),
      disposeBus: () async => busFactory.dispose(eventBus),
    );
  }

  /// Creates an in-memory workflow app (in-memory broker, backend, and store).
  ///
  /// Ideal for unit tests and examples since it requires no external services.
  /// When [module] or [tasks] are provided and
  /// [StemWorkerConfig.subscription] is omitted, the helper infers a worker
  /// subscription that includes the workflow queue plus the default queues
  /// declared on those task handlers.
  ///
  /// Example:
  /// ```dart
  /// final app = await StemWorkflowApp.inMemory(
  ///   workflows: [exampleWorkflow],
  /// );
  /// ```
  static Future<StemWorkflowApp> inMemory({
    StemModule? module,
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowRegistry? workflowRegistry,
    WorkflowIntrospectionSink? introspectionSink,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    return StemWorkflowApp.create(
      module: module,
      workflows: workflows,
      flows: flows,
      scripts: scripts,
      tasks: tasks,
      broker: StemBrokerFactory.inMemory(),
      backend: StemBackendFactory.inMemory(),
      storeFactory: WorkflowStoreFactory.inMemory(),
      eventBusFactory: WorkflowEventBusFactory.inMemory(),
      workerConfig: workerConfig,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
      workflowRegistry: workflowRegistry,
      introspectionSink: introspectionSink,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }

  /// Creates a workflow app from a single backend URL plus adapter wiring.
  ///
  /// This wires broker/backend and workflow-store factories from one URL and
  /// optional per-store overrides via [StemStack.fromUrl]. When [module] or
  /// [tasks] are provided and [StemWorkerConfig.subscription] is omitted, the
  /// helper infers a worker subscription that includes the workflow queue plus
  /// the default queues declared on those task handlers.
  static Future<StemWorkflowApp> fromUrl(
    String url, {
    StemModule? module,
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    Iterable<StemStoreAdapter> adapters = const [],
    StemStoreOverrides overrides = const StemStoreOverrides(),
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    bool uniqueTasks = false,
    Duration uniqueTaskDefaultTtl = const Duration(minutes: 5),
    String uniqueTaskNamespace = 'stem:unique',
    bool requireRevokeStore = false,
    RevokeStore? revokeStore,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowRegistry? workflowRegistry,
    WorkflowIntrospectionSink? introspectionSink,
    WorkflowEventBusFactory? eventBusFactory,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    final resolvedWorkerConfig = _resolveWorkflowWorkerConfig(
      workerConfig,
      module: module,
      tasks: tasks,
    );
    final stack = StemStack.fromUrl(
      url,
      adapters: adapters,
      overrides: overrides,
      workflows: true,
    );

    final app = await StemApp.fromUrl(
      url,
      adapters: adapters,
      overrides: overrides,
      stack: stack,
      workerConfig: resolvedWorkerConfig,
      uniqueTasks: uniqueTasks,
      uniqueTaskDefaultTtl: uniqueTaskDefaultTtl,
      uniqueTaskNamespace: uniqueTaskNamespace,
      requireRevokeStore: requireRevokeStore,
      revokeStore: revokeStore,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );

    try {
      return await create(
        module: module,
        workflows: workflows,
        flows: flows,
        scripts: scripts,
        tasks: tasks,
        stemApp: app,
        storeFactory: stack.workflowStore,
        eventBusFactory: eventBusFactory,
        workerConfig: resolvedWorkerConfig,
        pollInterval: pollInterval,
        leaseExtension: leaseExtension,
        workflowRegistry: workflowRegistry,
        introspectionSink: introspectionSink,
      );
    } on Object catch (error, stackTrace) {
      // fromUrl owns the app instance; clean it up when workflow bootstrap
      // fails.
      try {
        await app.shutdown();
      } on Object {
        // Keep the original bootstrap failure as the primary error.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Creates a workflow app backed by a shared [StemClient].
  ///
  /// When [module] or [tasks] are provided and
  /// [StemWorkerConfig.subscription] is omitted, the helper infers a worker
  /// subscription that includes the workflow queue plus the default queues
  /// declared on those task handlers.
  static Future<StemWorkflowApp> fromClient({
    required StemClient client,
    StemModule? module,
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    WorkflowStoreFactory? storeFactory,
    WorkflowEventBusFactory? eventBusFactory,
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowIntrospectionSink? introspectionSink,
  }) async {
    final resolvedWorkerConfig = _resolveWorkflowWorkerConfig(
      workerConfig,
      module: module,
      tasks: tasks,
    );
    final appInstance = await StemApp.fromClient(
      client,
      workerConfig: resolvedWorkerConfig,
    );
    return StemWorkflowApp.create(
      module: module,
      workflows: workflows,
      flows: flows,
      scripts: scripts,
      stemApp: appInstance,
      storeFactory: storeFactory,
      eventBusFactory: eventBusFactory,
      workerConfig: resolvedWorkerConfig,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
      workflowRegistry: client.workflowRegistry,
      introspectionSink: introspectionSink,
    );
  }
}

/// Convenience helpers for layering workflows onto an existing [StemApp].
extension StemAppWorkflowExtension on StemApp {
  /// Creates a workflow app on top of this shared task app.
  ///
  /// This reuses the existing broker/backend/worker wiring, so the current
  /// worker must already subscribe to the workflow queue and any task queues
  /// required by the supplied module or tasks.
  Future<StemWorkflowApp> createWorkflowApp({
    StemModule? module,
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    WorkflowStoreFactory? storeFactory,
    WorkflowEventBusFactory? eventBusFactory,
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
    WorkflowRegistry? workflowRegistry,
    WorkflowIntrospectionSink? introspectionSink,
  }) {
    return StemWorkflowApp.create(
      module: module ?? this.module,
      workflows: workflows,
      flows: flows,
      scripts: scripts,
      tasks: tasks,
      stemApp: this,
      storeFactory: storeFactory,
      eventBusFactory: eventBusFactory,
      workerConfig: workerConfig,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
      workflowRegistry: workflowRegistry,
      introspectionSink: introspectionSink,
    );
  }
}

void _validateReusableStemApp(
  StemApp app,
  StemWorkerConfig workerConfig,
) {
  final requiredQueues = workerConfig.subscription?.resolveQueues(
        workerConfig.queue,
      ) ??
      [workerConfig.queue];
  final workerQueues = app.worker.subscriptionQueues.toSet();
  final missingQueues = requiredQueues
      .map((queue) => queue.trim())
      .where((queue) => queue.isNotEmpty)
      .where((queue) => !workerQueues.contains(queue))
      .toList(growable: false);

  final requiredBroadcasts =
      workerConfig.subscription?.broadcastChannels ?? const <String>[];
  final workerBroadcasts = app.worker.subscriptionBroadcasts.toSet();
  final missingBroadcasts = requiredBroadcasts
      .map((channel) => channel.trim())
      .where((channel) => channel.isNotEmpty)
      .where((channel) => !workerBroadcasts.contains(channel))
      .toList(growable: false);

  if (missingQueues.isEmpty && missingBroadcasts.isEmpty) {
    return;
  }

  final details = <String>[
    if (missingQueues.isNotEmpty) 'queues=${missingQueues.join(",")}',
    if (missingBroadcasts.isNotEmpty)
      'broadcasts=${missingBroadcasts.join(",")}',
  ].join(' ');

  throw StateError(
    'StemWorkflowApp.create(stemApp: ...) requires the reused StemApp worker '
    'to already subscribe to the workflow/runtime queues it needs ($details). '
    'Create the StemApp with a matching workerConfig.subscription, or use '
    'StemClient.createWorkflowApp(...) / StemWorkflowApp.inMemory(...) so '
    'subscriptions can be inferred automatically.',
  );
}

StemWorkerConfig _resolveWorkflowWorkerConfig(
  StemWorkerConfig workerConfig, {
  StemModule? module,
  Iterable<TaskHandler<Object?>> tasks = const [],
}) {
  if (workerConfig.subscription != null) {
    return workerConfig;
  }

  final inferredSubscription =
      module?.inferWorkerSubscription(
        workflowQueue: workerConfig.queue,
        additionalTasks: tasks,
      ) ??
      (() {
        final tempModule = StemModule(tasks: tasks);
        return tempModule.inferWorkerSubscription(
          workflowQueue: workerConfig.queue,
        );
      })();

  if (inferredSubscription == null) {
    return workerConfig;
  }
  return workerConfig.copyWith(subscription: inferredSubscription);
}
