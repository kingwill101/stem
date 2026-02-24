import 'package:stem/stem.dart';
import 'package:stem_memory/stem_memory.dart';
import 'package:test/test.dart';

void main() {
  group('memoryBrokerFactory', () {
    test('creates and disposes an in-memory broker', () async {
      final factory = memoryBrokerFactory(
        namespace: 'factory-test',
        defaultVisibilityTimeout: const Duration(milliseconds: 500),
      );

      final broker = await factory.create();

      expect(broker, isA<InMemoryBroker>());
      await factory.dispose(broker);
    });

    test('falls back to close for non InMemoryBroker values', () async {
      final factory = memoryBrokerFactory();
      final broker = _TrackingBroker();

      await factory.dispose(broker);

      expect(broker.closed, isTrue);
    });
  });

  test('memoryResultBackendFactory creates and disposes backend', () async {
    final factory = memoryResultBackendFactory(
      defaultTtl: const Duration(minutes: 2),
      groupDefaultTtl: const Duration(minutes: 3),
      heartbeatTtl: const Duration(seconds: 10),
    );

    final backend = await factory.create();

    expect(backend, isA<InMemoryResultBackend>());
    await factory.dispose(backend);
  });

  test('memoryWorkflowStoreFactory creates a workflow store', () async {
    final clock = _FixedWorkflowClock(DateTime.utc(2025));
    final factory = memoryWorkflowStoreFactory(clock: clock);

    final store = await factory.create();

    expect(store, isA<InMemoryWorkflowStore>());
    final runId = await store.createRun(workflow: 'wf', params: const {});
    expect(runId, isNotEmpty);
  });

  test('memoryEventBusFactory creates an event bus bound to a store', () async {
    final store = InMemoryWorkflowStore();
    final factory = memoryEventBusFactory();

    final bus = await factory.create(store);

    expect(bus, isA<InMemoryEventBus>());
    expect(await bus.fanout('topic'), equals(0));
  });

  test('memoryScheduleStoreFactory creates a schedule store', () async {
    final calculator = ScheduleCalculator();
    final factory = memoryScheduleStoreFactory(calculator: calculator);

    final store = await factory.create();

    expect(store, isA<InMemoryScheduleStore>());
    expect(await store.list(), isEmpty);
  });

  test('memoryLockStoreFactory creates a lock store', () async {
    final factory = memoryLockStoreFactory();

    final store = await factory.create();

    expect(store, isA<InMemoryLockStore>());
    final lock = await store.acquire('resource');
    expect(lock, isNotNull);
    await lock!.release();
  });

  test(
    'memoryRevokeStoreFactory creates and disposes a revoke store',
    () async {
      final factory = memoryRevokeStoreFactory();

      final store = await factory.create();

      expect(store, isA<InMemoryRevokeStore>());
      await factory.dispose(store);
    },
  );
}

class _TrackingBroker implements Broker {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedWorkflowClock extends WorkflowClock {
  const _FixedWorkflowClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
