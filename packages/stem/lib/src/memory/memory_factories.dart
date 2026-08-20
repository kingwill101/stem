// This package depends on Stem's core internals while avoiding `stem.dart`
// import cycles created by the compatibility re-exports.
// ignore_for_file: implementation_imports
import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/scheduler/schedule_calculator.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';

import 'package:stem_memory/src/backend/in_memory_backend.dart';
import 'package:stem_memory/src/brokers/in_memory_broker.dart';
import 'package:stem_memory/src/control/in_memory_revoke_store.dart';
import 'package:stem_memory/src/scheduler/in_memory_lock_store.dart';
import 'package:stem_memory/src/scheduler/in_memory_schedule_store.dart';
import 'package:stem_memory/src/workflow/event_bus/in_memory_event_bus.dart';
import 'package:stem_memory/src/workflow/store/in_memory_workflow_store.dart';

/// Creates a [StemBrokerFactory] backed by [InMemoryBroker].
StemBrokerFactory memoryBrokerFactory({
  String namespace = 'stem',
  Duration defaultVisibilityTimeout = const Duration(seconds: 30),
}) {
  return StemBrokerFactory(
    create: () async => InMemoryBroker(
      namespace: namespace,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
    ),
    dispose: (broker) async {
      if (broker is InMemoryBroker) {
        broker.dispose();
        return;
      }
      await broker.close();
    },
  );
}

/// Creates a [StemBackendFactory] backed by [InMemoryResultBackend].
StemBackendFactory memoryResultBackendFactory({
  Duration defaultTtl = const Duration(days: 1),
  Duration groupDefaultTtl = const Duration(days: 1),
  Duration heartbeatTtl = const Duration(minutes: 1),
}) {
  return StemBackendFactory(
    create: () async => InMemoryResultBackend(
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    ),
    dispose: (backend) async {
      await backend.close();
    },
  );
}

/// Creates a [WorkflowStoreFactory] backed by [InMemoryWorkflowStore].
WorkflowStoreFactory memoryWorkflowStoreFactory({
  WorkflowClock clock = const SystemWorkflowClock(),
}) {
  return WorkflowStoreFactory(
    create: () async => InMemoryWorkflowStore(clock: clock),
  );
}

/// Creates a [WorkflowEventBusFactory] backed by [InMemoryEventBus].
WorkflowEventBusFactory memoryEventBusFactory() {
  return WorkflowEventBusFactory(
    create: (store) async => InMemoryEventBus(store),
  );
}

/// Creates a [ScheduleStoreFactory] backed by [InMemoryScheduleStore].
ScheduleStoreFactory memoryScheduleStoreFactory({
  ScheduleCalculator? calculator,
}) {
  return ScheduleStoreFactory(
    create: () async => InMemoryScheduleStore(calculator: calculator),
  );
}

/// Creates a [LockStoreFactory] backed by [InMemoryLockStore].
LockStoreFactory memoryLockStoreFactory() {
  return LockStoreFactory(create: () async => InMemoryLockStore());
}

/// Creates a [RevokeStoreFactory] backed by [InMemoryRevokeStore].
RevokeStoreFactory memoryRevokeStoreFactory() {
  return RevokeStoreFactory(
    create: () async => InMemoryRevokeStore(),
    dispose: (store) async => store.close(),
  );
}
