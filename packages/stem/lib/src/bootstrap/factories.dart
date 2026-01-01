import 'package:stem/src/backend/in_memory_backend.dart';
import 'package:stem/src/brokers/in_memory_broker.dart';
import 'package:stem/src/core/contracts.dart';
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
      dispose: (broker) async {
        if (broker is InMemoryBroker) {
          broker.dispose();
        }
      },
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
      dispose: (backend) async {
        if (backend is InMemoryResultBackend) {
          await backend.dispose();
        }
      },
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

/// Lightweight worker configuration used by the bootstrap helpers.
class StemWorkerConfig {
  /// Creates a worker configuration snapshot for bootstrap helpers.
  const StemWorkerConfig({
    this.queue = 'default',
    this.consumerName,
    this.concurrency,
    this.prefetchMultiplier = 2,
    this.prefetch,
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
}
