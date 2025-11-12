import '../workflow/core/flow.dart';
import '../workflow/core/workflow_definition.dart';
import '../workflow/core/workflow_script.dart';
import '../workflow/core/workflow_cancellation_policy.dart';
import '../workflow/core/run_state.dart';
import '../workflow/core/workflow_store.dart';
import '../workflow/core/event_bus.dart';
import '../workflow/runtime/workflow_runtime.dart';
import 'factories.dart';
import 'stem_app.dart';

/// Helper that bootstraps a workflow runtime on top of [StemApp].
///
/// This wrapper wires together broker/backend infrastructure, registers flows,
/// and exposes convenience helpers for scheduling and observing workflow runs
/// without having to manage [WorkflowRuntime] directly.
class StemWorkflowApp {
  StemWorkflowApp._({
    required this.app,
    required this.runtime,
    required this.store,
    required this.eventBus,
    required Future<void> Function() disposeStore,
    required Future<void> Function() disposeBus,
  }) : _disposeStore = disposeStore,
       _disposeBus = disposeBus;

  final StemApp app;
  final WorkflowRuntime runtime;
  final WorkflowStore store;
  final EventBus eventBus;

  final Future<void> Function() _disposeStore;
  final Future<void> Function() _disposeBus;

  bool _started = false;

  /// Starts the workflow runtime and the underlying Stem worker.
  ///
  /// Subsequent calls are ignored, so it is safe to call before every
  /// scheduling operation.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await runtime.start();
    await app.start();
  }

  /// Schedules a workflow run.
  ///
  /// Lazily starts the runtime on the first invocation so simple examples do
  /// not need to call [start] manually.
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

  /// Returns the current [RunState] of a workflow run, or `null` if not found.
  Future<RunState?> getRun(String runId) => store.get(runId);

  /// Polls the workflow store until the run reaches a terminal state.
  ///
  /// If [timeout] elapses, the most recent non-terminal state is returned so
  /// callers can inspect the suspension reason.
  Future<RunState?> waitForCompletion(
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    final startedAt = DateTime.now();
    while (true) {
      final state = await store.get(runId);
      if (state == null || state.isTerminal) {
        return state;
      }
      if (timeout != null && DateTime.now().difference(startedAt) >= timeout) {
        return state;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Stops the runtime, worker, and disposes associated resources.
  ///
  /// After shutdown the instance can be restarted by calling [start] again.
  Future<void> shutdown() async {
    await runtime.dispose();
    await app.shutdown();
    await _disposeBus();
    await _disposeStore();
    _started = false;
  }

  /// Creates a workflow app with custom backends and factories.
  ///
  /// Useful for wiring Redis/Postgres adapters or sharing an existing
  /// [StemApp] instance with job processors.
  static Future<StemWorkflowApp> create({
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    StemApp? stemApp,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    WorkflowStoreFactory? storeFactory,
    WorkflowEventBusFactory? eventBusFactory,
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
  }) async {
    final appInstance =
        stemApp ??
        await StemApp.create(
          tasks: const [],
          broker: broker ?? StemBrokerFactory.inMemory(),
          backend: backend ?? StemBackendFactory.inMemory(),
          workerConfig: workerConfig,
        );

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
      queue: workerConfig.queue,
    );

    appInstance.register(runtime.workflowRunnerHandler());

    for (final workflow in workflows) {
      runtime.registerWorkflow(workflow);
    }
    for (final flow in flows) {
      runtime.registerWorkflow(flow.definition);
    }
    for (final script in scripts) {
      runtime.registerWorkflow(script.definition);
    }

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
  static Future<StemWorkflowApp> inMemory({
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    StemWorkerConfig workerConfig = const StemWorkerConfig(queue: 'workflow'),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration leaseExtension = const Duration(seconds: 30),
  }) {
    return StemWorkflowApp.create(
      workflows: workflows,
      flows: flows,
      scripts: scripts,
      broker: StemBrokerFactory.inMemory(),
      backend: StemBackendFactory.inMemory(),
      storeFactory: WorkflowStoreFactory.inMemory(),
      eventBusFactory: WorkflowEventBusFactory.inMemory(),
      workerConfig: workerConfig,
      pollInterval: pollInterval,
      leaseExtension: leaseExtension,
    );
  }
}
