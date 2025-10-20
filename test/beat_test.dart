import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/stem.dart';

void main() {
  group('Beat', () {
    test('fires schedule once per interval', () async {
      final broker = InMemoryRedisBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
        tickInterval: const Duration(milliseconds: 10),
      )..start();

      await store.upsert(
        ScheduleEntry(
          id: 'cleanup',
          taskName: 'noop',
          queue: 'default',
          spec: 'every:100ms',
        ),
      );

      final events = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-beat',
        concurrency: 1,
        prefetchMultiplier: 1,
      );
      worker.events.listen(events.add);
      await worker.start();

      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(
        events.where((e) => e.type == WorkerEventType.completed).length,
        greaterThanOrEqualTo(2),
      );

      await worker.shutdown();
      await beat.stop();
      broker.dispose();
    });

    test('only one beat instance dispatches when locks used', () async {
      final broker = InMemoryRedisBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final store = InMemoryScheduleStore();
      final lockStore = InMemoryLockStore();
      final beatA = Beat(
        store: store,
        broker: broker,
        lockStore: lockStore,
        tickInterval: const Duration(milliseconds: 10),
      );
      final beatB = Beat(
        store: store,
        broker: broker,
        lockStore: lockStore,
        tickInterval: const Duration(milliseconds: 10),
      );

      await store.upsert(
        ScheduleEntry(
          id: 'unique',
          taskName: 'noop',
          queue: 'default',
          spec: 'every:100ms',
        ),
      );

      final completions = <String>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-lock',
        concurrency: 1,
        prefetchMultiplier: 1,
      );
      worker.events.listen((e) {
        if (e.type == WorkerEventType.completed && e.envelope != null) {
          completions.add(e.envelope!.id);
        }
      });
      await worker.start();

      await beatA.runOnce();
      await beatB.runOnce();

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(completions.toSet().length, equals(completions.length));

      await worker.shutdown();
      await beatA.stop();
      await beatB.stop();
      broker.dispose();
    });
  });
}

class _NoopTask implements TaskHandler<void> {
  @override
  String get name => 'noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
