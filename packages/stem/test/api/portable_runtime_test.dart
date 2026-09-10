// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:stem/portable.dart';
import 'package:test/test.dart';

void main() {
  test('status-only stores support publishing and observing results', () async {
    final publisher = _Publisher();
    final store = _StatusStore();
    final stem = Stem.withPublisher(
      publisher: publisher,
      taskStatusStore: store,
    );
    final definition = TaskDefinition<Map<String, Object?>, int>(
      name: 'echo',
      encodeArgs: (args) => args,
    );
    final id = await stem.enqueueCall(definition.buildCall(const {}));
    expect((await stem.getTaskStatus(id))?.state, TaskState.queued);
    expect(await stem.getGroupStatus('absent'), isNull);
    await store.set(id, TaskState.succeeded, payload: 42);
    expect((await stem.waitForTask<int>(id))?.value, 42);
    await stem.close();
  });

  test('one-shot scheduling finishes without a periodic timer', () async {
    final publisher = _Publisher();
    final store = _ScheduleStore();
    var periodicTimers = 0;
    await runZoned(
      () => ScheduleRunner(store: store, publisher: publisher).runOnce(),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          periodicTimers++;
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ),
    );
    expect(periodicTimers, 0);
    expect(publisher.envelopes.single.name, 'scheduled');
    expect(store.executed, ['schedule']);
    await ScheduleRunner(store: store, publisher: publisher).runOnce();
    expect(publisher.envelopes, hasLength(1));
  });

  for (final failPublish in [false, true]) {
    test(
      'one-shot locks and timers are released (failure=$failPublish)',
      () async {
        final publisher = _Publisher()..failPublish = failPublish;
        final locks = _LockStore();
        final timers = <Timer>[];
        await runZoned(
          () => ScheduleRunner(
            store: _ScheduleStore(),
            publisher: publisher,
            lockStore: locks,
          ).runOnce(),
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        expect(timers, hasLength(1));
        expect(timers.single.isActive, isFalse);
        expect(locks.lock.released, isTrue);
        expect(locks.lock.renewals, 1);
      },
    );
  }

  test('mixed batches settle each message independently', () async {
    final registry = InMemoryTaskRegistry()
      ..register(
        FunctionTaskHandler<Object?>.inline(
          name: 'work',
          entrypoint: (context, args) async {
            switch (args['kind']) {
              case 'retry':
                await context.retry(
                  countdown: const Duration(seconds: 3),
                  maxRetries: 3,
                );
              case 'fail':
                throw StateError('terminal');
            }
            return 42;
          },
        ),
      );
    final processor = TaskProcessor(registry: registry);
    final dispositions = <String, String>{};
    for (final kind in ['success', 'retry', 'fail']) {
      final outcome = await processor.process(
        Envelope(id: kind, name: 'work', args: {'kind': kind}),
        // Native delivery counters are one-based; normalize at the boundary.
        deliveryAttempt: 1 - 1,
      );
      switch (outcome) {
        case TaskProcessSuccess():
          dispositions[outcome.taskId] = 'ack';
        case TaskProcessRetry():
          expect(outcome.delay, const Duration(seconds: 3));
          expect(outcome.nextAttempt, 1);
          expect(outcome.nextEnvelope.id, outcome.taskId);
          dispositions[outcome.taskId] = 'retry';
        case TaskProcessFailure():
          dispositions[outcome.taskId] = 'dlq';
        default:
          fail('Unexpected disposition: $outcome');
      }
    }
    expect(dispositions, {'success': 'ack', 'retry': 'retry', 'fail': 'dlq'});
  });

  test(
    'terminal persistence suppresses sequential duplicate execution',
    () async {
      var executions = 0;
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<Object?>.inline(
              name: 'work',
              entrypoint: (context, args) async => ++executions,
            ),
          ),
      );
      final envelope = Envelope(id: 'same', name: 'work', args: const {});
      final first = await processor.process(envelope);
      expect(first, isA<TaskProcessSuccess>());
      final second = await processor.process(
        envelope,
        existingStatus: TaskStatus(
          id: envelope.id,
          state: TaskState.succeeded,
          attempt: 0,
        ),
      );
      expect(second, isA<TaskProcessSkipped>());
      expect(executions, 1);
    },
  );

  test(
    'without an atomic claim concurrent deliveries can both execute',
    () async {
      var executions = 0;
      final entered = Completer<void>();
      final release = Completer<void>();
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()
          ..register(
            FunctionTaskHandler<Object?>.inline(
              name: 'work',
              entrypoint: (context, args) async {
                if (++executions == 2) entered.complete();
                await release.future;
                return null;
              },
            ),
          ),
      );
      final envelope = Envelope(id: 'same', name: 'work', args: const {});
      final results = Future.wait([
        processor.process(envelope),
        processor.process(envelope),
      ]);
      await entered.future;
      release.complete();
      expect(await results, everyElement(isA<TaskProcessSuccess>()));
      expect(executions, 2);
    },
  );
}

class _Publisher implements TaskPublisher {
  final envelopes = <Envelope>[];
  bool failPublish = false;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    if (failPublish) throw StateError('publish failed');
    envelopes.add(envelope);
  }
}

class _Lock extends Lock {
  bool released = false;
  int renewals = 0;

  @override
  String get key => 'schedule';

  @override
  String get owner => 'test';

  @override
  Future<bool> renew(Duration ttl) async {
    renewals++;
    return true;
  }

  @override
  Future<void> release() async {
    released = true;
  }
}

class _LockStore extends LockStore {
  final lock = _Lock();

  @override
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  }) async => lock;

  @override
  Future<String?> ownerOf(String key) async => lock.owner;

  @override
  Future<bool> renew(String key, String owner, Duration ttl) => lock.renew(ttl);

  @override
  Future<bool> release(String key, String owner) async {
    await lock.release();
    return true;
  }
}

class _StatusStore implements TaskStatusStore {
  final statuses = <String, TaskStatus>{};

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    statuses[taskId] = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      attempt: attempt,
      meta: meta,
    );
  }

  @override
  Future<TaskStatus?> get(String taskId) async => statuses[taskId];

  @override
  Stream<TaskStatus> watch(String taskId) => const Stream.empty();

  @override
  Future<void> expire(String taskId, Duration ttl) async {}

  @override
  Future<TaskStatusPage> listTaskStatuses(
    TaskStatusListRequest request,
  ) async => const TaskStatusPage(items: []);
}

class _ScheduleStore implements ScheduleStore {
  final executed = <String>[];
  final entry = ScheduleEntry(
    id: 'schedule',
    taskName: 'scheduled',
    queue: 'default',
    spec: IntervalScheduleSpec(every: const Duration(minutes: 1)),
  );

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) async =>
      executed.isEmpty ? [entry] : [];

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    executed.add(id);
  }

  @override
  Future<ScheduleEntry?> get(String id) async => id == entry.id ? entry : null;

  @override
  Future<List<ScheduleEntry>> list({int? limit}) async => [entry];

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> upsert(ScheduleEntry entry) async {}
}
