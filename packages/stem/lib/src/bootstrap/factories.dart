import '../backend/in_memory_backend.dart';
import '../brokers/in_memory_broker.dart';
import '../core/contracts.dart';
import '../workflow/core/event_bus.dart';
import '../workflow/core/workflow_store.dart';
import '../workflow/event_bus/in_memory_event_bus.dart';
import '../workflow/store/in_memory_workflow_store.dart';

/// Wrapper for constructing and disposing Stem resources lazily.
class StemResourceFactory<T> {
  const StemResourceFactory({
    required Future<T> Function() create,
    Future<void> Function(T value)? dispose,
  }) : _create = create,
       _dispose = dispose;

  final Future<T> Function() _create;
  final Future<void> Function(T value)? _dispose;

  Future<T> create() => _create();

  Future<void> dispose(T value) async {
    final disposer = _dispose;
    if (disposer != null) {
      await disposer(value);
    }
  }
}

/// Factory for building [Broker] instances.
class StemBrokerFactory extends StemResourceFactory<Broker> {
  StemBrokerFactory({required super.create, super.dispose});

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
  StemBackendFactory({required super.create, super.dispose});

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
  WorkflowStoreFactory({required super.create, super.dispose});

  factory WorkflowStoreFactory.inMemory() {
    return WorkflowStoreFactory(create: () async => InMemoryWorkflowStore());
  }
}

/// Factory for building workflow [EventBus] instances that depend on a store.
class WorkflowEventBusFactory {
  WorkflowEventBusFactory({
    required Future<EventBus> Function(WorkflowStore store) create,
    Future<void> Function(EventBus value)? dispose,
  }) : _create = create,
       _dispose = dispose;

  final Future<EventBus> Function(WorkflowStore store) _create;
  final Future<void> Function(EventBus value)? _dispose;

  Future<EventBus> create(WorkflowStore store) => _create(store);

  Future<void> dispose(EventBus bus) async {
    final disposer = _dispose;
    if (disposer != null) {
      await disposer(bus);
    }
  }

  factory WorkflowEventBusFactory.inMemory() {
    return WorkflowEventBusFactory(
      create: (store) async => InMemoryEventBus(store),
    );
  }
}

/// Lightweight worker configuration used by the bootstrap helpers.
class StemWorkerConfig {
  const StemWorkerConfig({
    this.queue = 'default',
    this.consumerName,
    this.concurrency,
    this.prefetchMultiplier = 2,
    this.prefetch,
  });

  final String queue;
  final String? consumerName;
  final int? concurrency;
  final int prefetchMultiplier;
  final int? prefetch;
}
