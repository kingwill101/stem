import 'dart:async';
import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  Future<void> waitForEvents(
    List<WorkerEvent> events, {
    required int completed,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final done = events
          .where((event) => event.type == WorkerEventType.completed)
          .length;
      if (done >= completed) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('Beat', () {
    test('fires schedule once per interval', () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
        tickInterval: const Duration(milliseconds: 10),
      );
      await beat.start();

      await store.upsert(
        ScheduleEntry(
          id: 'cleanup',
          taskName: 'noop',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(milliseconds: 100)),
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

      await waitForEvents(events, completed: 2);
      expect(
        events.where((e) => e.type == WorkerEventType.completed).length,
        greaterThanOrEqualTo(2),
      );

      await worker.shutdown();
      await beat.stop();
      broker.dispose();
    });

    test('signs scheduled tasks when signer provided', () async {
      final secret = base64.encode(utf8.encode('beat-secret'));
      final signingConfig = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS': 'primary:$secret',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });

      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
        tickInterval: const Duration(milliseconds: 10),
        signer: PayloadSigner(signingConfig),
      );
      await beat.start();

      await store.upsert(
        ScheduleEntry(
          id: 'signed-cleanup',
          taskName: 'noop',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(milliseconds: 100)),
        ),
      );

      final events = <WorkerEvent>[];
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-beat-signed',
        concurrency: 1,
        prefetchMultiplier: 1,
        signer: PayloadSigner(signingConfig),
      );
      worker.events.listen(events.add);
      await worker.start();

      await waitForEvents(events, completed: 2);

      expect(
        events.where((e) => e.type == WorkerEventType.completed).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        events.where((e) => e.type == WorkerEventType.failed).length,
        equals(0),
      );

      await worker.shutdown();
      await beat.stop();
      broker.dispose();
    });

    test('disables one-shot schedules after execution', () async {
      final broker = InMemoryBroker();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final backend = InMemoryResultBackend();
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
        tickInterval: const Duration(milliseconds: 10),
      );

      final runAt = DateTime.now().add(const Duration(milliseconds: 100));
      await store.upsert(
        ScheduleEntry(
          id: 'once',
          taskName: 'noop',
          queue: 'default',
          spec: ClockedScheduleSpec(runAt: runAt),
        ),
      );

      await beat.start();
      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-once',
        concurrency: 1,
      );
      await worker.start();

      await Future<void>.delayed(const Duration(milliseconds: 400));

      final entry = await store.get('once');
      expect(entry, isNotNull);
      expect(entry!.enabled, isFalse);

      await worker.shutdown();
      await beat.stop();
      broker.dispose();
    });

    test('only one beat instance dispatches when locks used', () async {
      final broker = InMemoryBroker();
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
          spec: IntervalScheduleSpec(every: const Duration(milliseconds: 100)),
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

    test('emits scheduler signals on successful dispatch', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());
      final broker = InMemoryBroker();
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
      );

      await store.upsert(
        ScheduleEntry(
          id: 'demo',
          taskName: 'noop',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(milliseconds: 10)),
        ),
      );

      final due = Completer<void>();
      final dispatched = Completer<ScheduleEntryDispatchedPayload>();
      final subs = <SignalSubscription>[
        StemSignals.onScheduleEntryDue((payload, _) {
          if (payload.entry.id == 'demo' && !due.isCompleted) {
            due.complete();
          }
        }),
        StemSignals.onScheduleEntryDispatched((payload, _) {
          if (payload.entry.id == 'demo' && !dispatched.isCompleted) {
            dispatched.complete(payload);
          }
        }),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await beat.runOnce();

      await due.future.timeout(const Duration(seconds: 1));
      final dispatchedPayload = await dispatched.future.timeout(
        const Duration(seconds: 1),
      );
      expect(dispatchedPayload.entry.id, 'demo');

      for (final sub in subs) {
        sub.cancel();
      }
      await beat.stop();
      broker.dispose();
    });

    test('emits scheduler failure signal when publish fails', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());
      final broker = _ThrowingBroker();
      final store = InMemoryScheduleStore();
      final beat = Beat(
        store: store,
        broker: broker,
        lockStore: InMemoryLockStore(),
      );

      await store.upsert(
        ScheduleEntry(
          id: 'failing',
          taskName: 'noop',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(milliseconds: 10)),
        ),
      );

      final failure = Completer<ScheduleEntryFailedPayload>();
      final subs = <SignalSubscription>[
        StemSignals.onScheduleEntryFailed((payload, _) {
          if (payload.entry.id == 'failing' && !failure.isCompleted) {
            failure.complete(payload);
          }
        }),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await beat.runOnce();

      final failedPayload = await failure.future.timeout(
        const Duration(seconds: 1),
      );
      expect(failedPayload.entry.id, 'failing');
      expect(failedPayload.error, isA<StateError>());

      for (final sub in subs) {
        sub.cancel();
      }
      await beat.stop();
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
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

class _ThrowingBroker extends InMemoryBroker {
  bool _throwOnce = true;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) {
    if (_throwOnce) {
      _throwOnce = false;
      return Future.error(StateError('publish failed'));
    }
    return super.publish(envelope, routing: routing);
  }
}
