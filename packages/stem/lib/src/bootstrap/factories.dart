import 'package:stem/src/backend/in_memory_backend.dart';
import 'package:stem/src/brokers/in_memory_broker.dart';
import 'package:stem/src/control/in_memory_revoke_store.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/observability/config.dart';
import 'package:stem/src/observability/heartbeat_transport.dart';
import 'package:stem/src/scheduler/in_memory_lock_store.dart';
import 'package:stem/src/scheduler/in_memory_schedule_store.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/worker/worker_config.dart';
import 'package:stem/src/workflow/core/event_bus.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/event_bus/in_memory_event_bus.dart';
import 'package:stem/src/workflow/store/in_memory_workflow_store.dart';

/// Wrapper for constructing and disposing Stem resources lazily.
class StemResourceFactory<T> {
  /// Creates a resource factory with create/dispose hooks.
  const StemResourceFactory({
    required Future<T> Function() create,
    Future<void> Function(T value)? dispose,
  }) : _create = create,
       _dispose = dispose;

  final Future<T> Function() _create;
  final Future<void> Function(T value)? _dispose;

  /// Creates a new resource instance.
  Future<T> create() => _create();

  /// Disposes a resource instance if a disposer is configured.
  Future<void> dispose(T value) async {
    final disposer = _dispose;
    if (disposer != null) {
      await disposer(value);
    }
  }
}

/// Factory for building [Broker] instances.
class StemBrokerFactory extends StemResourceFactory<Broker> {
  /// Creates a broker factory from create/dispose hooks.
  StemBrokerFactory({required super.create, super.dispose});

  /// Creates an in-memory broker factory.
  factory StemBrokerFactory.inMemory() {
    return StemBrokerFactory(
      create: () async => InMemoryBroker(),
      dispose: (broker) => broker.close(),
    );
  }
}

/// Factory for building [ResultBackend] instances.
class StemBackendFactory extends StemResourceFactory<ResultBackend> {
  /// Creates a backend factory from create/dispose hooks.
  StemBackendFactory({required super.create, super.dispose});

  /// Creates an in-memory backend factory.
  factory StemBackendFactory.inMemory() {
    return StemBackendFactory(
      create: () async => InMemoryResultBackend(),
      dispose: (backend) => backend.close(),
    );
  }
}

/// Factory for building [WorkflowStore] instances.
class WorkflowStoreFactory extends StemResourceFactory<WorkflowStore> {
  /// Creates a workflow store factory from create/dispose hooks.
  WorkflowStoreFactory({required super.create, super.dispose});

  /// Creates an in-memory workflow store factory.
  factory WorkflowStoreFactory.inMemory() {
    return WorkflowStoreFactory(create: () async => InMemoryWorkflowStore());
  }
}

/// Factory for building workflow [EventBus] instances that depend on a store.
class WorkflowEventBusFactory {
  /// Creates an event bus factory with create/dispose hooks.
  WorkflowEventBusFactory({
    required Future<EventBus> Function(WorkflowStore store) create,
    Future<void> Function(EventBus value)? dispose,
  }) : _create = create,
       _dispose = dispose;

  /// Creates an in-memory event bus factory.
  factory WorkflowEventBusFactory.inMemory() {
    return WorkflowEventBusFactory(
      create: (store) async => InMemoryEventBus(store),
    );
  }

  final Future<EventBus> Function(WorkflowStore store) _create;
  final Future<void> Function(EventBus value)? _dispose;

  /// Creates an [EventBus] bound to the provided [store].
  Future<EventBus> create(WorkflowStore store) => _create(store);

  /// Disposes an [EventBus] if a disposer is configured.
  Future<void> dispose(EventBus bus) async {
    final disposer = _dispose;
    if (disposer != null) {
      await disposer(bus);
    }
  }
}

/// Factory for building [ScheduleStore] instances.
class ScheduleStoreFactory extends StemResourceFactory<ScheduleStore> {
  /// Creates a schedule store factory from create/dispose hooks.
  ScheduleStoreFactory({required super.create, super.dispose});

  /// Creates an in-memory schedule store factory.
  factory ScheduleStoreFactory.inMemory() {
    return ScheduleStoreFactory(create: () async => InMemoryScheduleStore());
  }
}

/// Factory for building [LockStore] instances.
class LockStoreFactory extends StemResourceFactory<LockStore> {
  /// Creates a lock store factory from create/dispose hooks.
  LockStoreFactory({required super.create, super.dispose});

  /// Creates an in-memory lock store factory.
  factory LockStoreFactory.inMemory() {
    return LockStoreFactory(create: () async => InMemoryLockStore());
  }
}

/// Factory for building [RevokeStore] instances.
class RevokeStoreFactory extends StemResourceFactory<RevokeStore> {
  /// Creates a revoke store factory from create/dispose hooks.
  RevokeStoreFactory({required super.create, super.dispose});

  /// Creates an in-memory revoke store factory.
  factory RevokeStoreFactory.inMemory() {
    return RevokeStoreFactory(
      create: () async => InMemoryRevokeStore(),
      dispose: (store) => store.close(),
    );
  }
}

/// Worker configuration used by the bootstrap helpers.
class StemWorkerConfig {
  /// Creates a worker configuration snapshot for bootstrap helpers.
  const StemWorkerConfig({
    this.queue = 'default',
    this.consumerName = 'default-worker',
    this.concurrency,
    this.prefetchMultiplier = 2,
    this.prefetch,
    this.rateLimiter,
    this.middleware,
    this.revokeStore,
    this.uniqueTaskCoordinator,
    this.retryStrategy,
    this.subscription,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.workerHeartbeatInterval,
    this.heartbeatTransport,
    this.heartbeatNamespace = 'stem',
    this.autoscale,
    this.lifecycle,
    this.observability,
    this.signer,
  });

  /// Queue name used by the worker.
  final String queue;

  /// Optional consumer name override for the worker.
  final String? consumerName;

  /// Optional concurrency override for worker tasks.
  final int? concurrency;

  /// Multiplier used when calculating prefetch size.
  final int prefetchMultiplier;

  /// Optional prefetch override for the worker.
  final int? prefetch;

  /// Optional rate limiter used by the worker.
  final RateLimiter? rateLimiter;

  /// Optional middleware chain applied by the worker.
  final List<Middleware>? middleware;

  /// Optional revoke store used for worker control.
  final RevokeStore? revokeStore;

  /// Optional unique task coordinator used by the worker.
  final UniqueTaskCoordinator? uniqueTaskCoordinator;

  /// Optional retry strategy used by the worker.
  final RetryStrategy? retryStrategy;

  /// Optional routing subscription for the worker.
  final RoutingSubscription? subscription;

  /// Interval between task heartbeats.
  final Duration heartbeatInterval;

  /// Optional override for worker-level heartbeat cadence.
  final Duration? workerHeartbeatInterval;

  /// Optional transport for emitting worker heartbeats.
  final HeartbeatTransport? heartbeatTransport;

  /// Namespace for worker heartbeat/control events.
  final String heartbeatNamespace;

  /// Optional autoscale configuration for the worker.
  final WorkerAutoscaleConfig? autoscale;

  /// Optional lifecycle configuration for the worker.
  final WorkerLifecycleConfig? lifecycle;

  /// Optional observability configuration for the worker.
  final ObservabilityConfig? observability;

  /// Optional payload signer used to verify envelopes.
  final PayloadSigner? signer;
}
