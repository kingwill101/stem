import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/bootstrap/stem_app.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/workflow/core/event_bus.dart';
import 'package:stem/src/workflow/core/flow.dart';
import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
import 'package:stem/src/workflow/core/workflow_script.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/runtime/workflow_introspection.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';
import 'package:stem/src/workflow/runtime/workflow_runtime.dart';

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
    final startedAt = DateTime.now();
    while (true) {
      final state = await store.get(runId);
      if (state == null) {
        return null;
      }
      if (state.isTerminal) {
        return _buildResult(state, decode, timedOut: false);
      }
      if (timeout != null && DateTime.now().difference(startedAt) >= timeout) {
        return _buildResult(state, decode, timedOut: true);
      }
      await Future<void>.delayed(pollInterval);
    }
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
  /// [StemApp] instance with job processors.
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
    WorkflowRegistry? workflowRegistry,
    WorkflowIntrospectionSink? introspectionSink,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    final appInstance =
        stemApp ??
        await StemApp.create(
          broker: broker ?? StemBrokerFactory.inMemory(),
          backend: backend ?? StemBackendFactory.inMemory(),
          workerConfig: workerConfig,
          encoderRegistry: encoderRegistry,
          resultEncoder: resultEncoder,
          argsEncoder: argsEncoder,
          additionalEncoders: additionalEncoders,
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
      registry: workflowRegistry,
      introspectionSink: introspectionSink,
    );

    appInstance.register(runtime.workflowRunnerHandler());

    workflows.forEach(runtime.registerWorkflow);
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
  ///
  /// Example:
  /// ```dart
  /// final app = await StemWorkflowApp.inMemory(
  ///   workflows: [exampleWorkflow],
  /// );
  /// ```
  static Future<StemWorkflowApp> inMemory({
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
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
      workflowRegistry: workflowRegistry,
      introspectionSink: introspectionSink,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }
}
