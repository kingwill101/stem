import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/android_status_notifications.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:stem/stem.dart';

void main() {
  for (final terminal in [
    WorkerEventType.completed,
    WorkerEventType.failed,
    WorkerEventType.revoked,
  ]) {
    test('only matching $terminal events settle interrupted tasks', () async {
      final app = await StemApp.inMemory();
      final first = _EventWorker('first');
      final second = _EventWorker('second');
      addTearDown(app.close);
      for (final id in ['a', 'b', 'ongoing']) {
        await app.backend.set(
          id,
          TaskState.running,
          meta: const {'queue': queueName, 'batchId': 'batch'},
        );
      }
      final shown = <PhotoQueueStatus>[];
      Completer<PhotoQueueStatus>? next;
      final observer = PhotoQueueNotificationObserver(
        app,
        AndroidStatusNotifications(
          show: (status) async {
            shown.add(status);
            if (next != null && !next!.isCompleted) next!.complete(status);
          },
        ),
        workers: [first, second],
      );
      await observer.start();
      Future<void> interrupt(_EventWorker worker, String id, int attempt) =>
          StemSignals.taskInterrupted.emit(
            TaskInterruptedPayload(
              envelope: Envelope(
                id: id,
                name: 'photo',
                args: const {},
                attempt: attempt,
              ),
              worker: WorkerInfo(
                id: worker.workerId,
                queues: const [queueName],
                broadcasts: const [],
              ),
              priorStatus: TaskStatus(
                id: id,
                state: TaskState.running,
                attempt: attempt,
              ),
              policy: TaskRecoveryPolicy.retry,
            ),
          );
      Future<PhotoQueuePhase> emit(
        _EventWorker worker,
        WorkerEventType type, {
        String? id,
        int attempt = 0,
      }) async {
        final received = next = Completer<PhotoQueueStatus>();
        worker.controller.add(
          WorkerEvent(
            type: type,
            envelope: id == null
                ? null
                : Envelope(
                    id: id,
                    name: 'photo',
                    args: const {},
                    attempt: attempt,
                  ),
          ),
        );
        return (await received.future.timeout(
          const Duration(seconds: 2),
        )).phase;
      }

      try {
        await interrupt(first, 'a', 0);
        await interrupt(first, 'a', 0); // Duplicate evidence is idempotent.
        await interrupt(second, 'b', 1);
        await interrupt(first, 'b', 0); // Older evidence cannot downgrade it.
        expect(shown.last.phase, PhotoQueuePhase.interrupted);
        expect(
          await emit(first, WorkerEventType.completed, id: 'unrelated'),
          PhotoQueuePhase.interrupted,
        );
        expect(
          await emit(first, WorkerEventType.completed),
          PhotoQueuePhase.interrupted,
        );
        // A retry may finish on a different worker, but b is still recovering.
        expect(
          await emit(second, WorkerEventType.completed, id: 'a', attempt: 1),
          PhotoQueuePhase.interrupted,
        );
        expect(
          await emit(first, WorkerEventType.retried, id: 'b', attempt: 1),
          PhotoQueuePhase.interrupted,
        );
        expect(
          await emit(first, terminal, id: 'b', attempt: 0),
          PhotoQueuePhase.interrupted,
        );
        await app.backend.set(
          'b',
          terminal == WorkerEventType.failed
              ? TaskState.failed
              : terminal == WorkerEventType.revoked
              ? TaskState.cancelled
              : TaskState.succeeded,
          attempt: 2,
          meta: const {'queue': queueName, 'batchId': 'batch'},
        );
        expect(
          await emit(first, terminal, id: 'b', attempt: 2),
          PhotoQueuePhase.processing,
        );
      } finally {
        await observer.finish(
          const WorkerRunOutcome(
            reason: WorkerRunStopReason.idle,
            deliveriesProcessed: 0,
            elapsed: Duration.zero,
          ),
        );
        await first.controller.close();
        await second.controller.close();
      }
    });
  }

  test(
    'notification observation includes and disconnects additional workers',
    () async {
      final primary = await StemApp.inMemory(
        workerConfig: const StemWorkerConfig(
          queue: queueName,
          consumerName: 'observe-a',
        ),
      );
      final secondary = await StemApp.inMemory(
        workerConfig: const StemWorkerConfig(
          queue: queueName,
          consumerName: 'observe-b',
        ),
      );
      addTearDown(primary.close);
      addTearDown(secondary.close);
      await primary.backend.set(
        'photo',
        TaskState.running,
        meta: const {'queue': queueName, 'batchId': 'batch'},
      );
      final shown = <PhotoQueueStatus>[];
      final observer = PhotoQueueNotificationObserver(
        primary,
        AndroidStatusNotifications(show: (status) async => shown.add(status)),
        workers: [primary.worker, secondary.worker],
      );
      await observer.start();
      Future<void> interrupt(StemApp owner) => StemSignals.taskInterrupted.emit(
        TaskInterruptedPayload(
          envelope: Envelope(id: 'photo', name: 'photo', args: const {}),
          worker: WorkerInfo(
            id: owner.worker.workerId,
            queues: const [queueName],
            broadcasts: const [],
          ),
          priorStatus: TaskStatus(
            id: 'photo',
            state: TaskState.running,
            attempt: 0,
          ),
          policy: TaskRecoveryPolicy.retry,
        ),
      );
      await interrupt(secondary);
      expect(shown.last.phase, PhotoQueuePhase.interrupted);
      expect(shown, hasLength(2));
      await observer.finish(
        const WorkerRunOutcome(
          reason: WorkerRunStopReason.idle,
          deliveriesProcessed: 0,
          elapsed: Duration.zero,
        ),
      );
      final count = shown.length;
      await interrupt(primary);
      await interrupt(secondary);
      expect(shown, hasLength(count));
    },
  );

  test(
    'interruption signal is worker-scoped and disconnected at finish',
    () async {
      final app = await StemApp.create(
        tasks: const [],
        broker: StemBrokerFactory.inMemory(),
        backend: StemBackendFactory.inMemory(),
      );
      addTearDown(app.close);
      const meta = {'queue': queueName, 'batchId': 'batch'};
      await app.backend.set('photo', TaskState.running, attempt: 0, meta: meta);
      final shown = <PhotoQueueStatus>[];
      final observer = PhotoQueueNotificationObserver(
        app,
        AndroidStatusNotifications(show: (status) async => shown.add(status)),
      );
      await observer.start();
      Future<void> interrupt(String workerId) =>
          StemSignals.taskInterrupted.emit(
            TaskInterruptedPayload(
              envelope: Envelope(id: 'photo', name: 'photo', args: const {}),
              worker: WorkerInfo(
                id: workerId,
                queues: const [queueName],
                broadcasts: const [],
              ),
              priorStatus: TaskStatus(
                id: 'photo',
                state: TaskState.running,
                attempt: 0,
              ),
              policy: TaskRecoveryPolicy.retry,
            ),
          );
      await interrupt('unrelated-worker');
      expect(shown.length, 1);
      await interrupt(app.worker.workerId);
      expect(shown.last.phase, PhotoQueuePhase.interrupted);
      expect(shown.last.ongoing, isFalse);
      expect(shown.last.completed, 0);
      expect(shown.last.body, contains('retry policy may defer'));
      await observer.finish(
        WorkerRunOutcome(
          reason: WorkerRunStopReason.idle,
          deliveriesProcessed: 0,
          elapsed: Duration.zero,
        ),
      );
      final length = shown.length;
      await interrupt(app.worker.workerId);
      expect(
        shown.length,
        length,
        reason: 'Finished callbacks must unsubscribe.',
      );
    },
  );

  test(
    'final durable read replaces active status with completed counts',
    () async {
      final app = await StemApp.create(
        tasks: const [],
        broker: StemBrokerFactory.inMemory(),
        backend: StemBackendFactory.inMemory(),
      );
      addTearDown(app.close);
      await app.backend.set(
        'historical-photo',
        TaskState.failed,
        attempt: 0,
        meta: {'queue': queueName, 'batchId': 'old-batch'},
      );
      const meta = {'queue': queueName, 'batchId': 'batch', 'batchSize': 12};
      await app.backend.set('photo', TaskState.queued, attempt: 0, meta: meta);
      final shown = <PhotoQueueStatus>[];
      final observer = PhotoQueueNotificationObserver(
        app,
        AndroidStatusNotifications(show: (status) async => shown.add(status)),
      );
      await observer.start();
      expect(shown.single.ongoing, isTrue);
      await app.backend.set(
        'photo',
        TaskState.succeeded,
        attempt: 0,
        meta: meta,
      );
      await observer.finish(
        WorkerRunOutcome(
          reason: WorkerRunStopReason.idle,
          deliveriesProcessed:
              0, // Deliberately not the source of photo counts.
          elapsed: Duration.zero,
        ),
      );
      expect(shown.last.phase, PhotoQueuePhase.completed);
      expect(shown.last.completed, 1);
      expect(shown.last.total, 1);
      expect(shown.last.failed, 0);
      expect(shown.last.ongoing, isFalse);
    },
  );

  group('active or latest batch counts', () {
    TaskStatusRecord photo(
      String batch,
      TaskState state,
      int created, {
      int? updated,
    }) => TaskStatusRecord(
      status: TaskStatus(
        id: '$batch-$created-${state.name}',
        state: state,
        attempt: 0,
        meta: {'batchId': batch, 'batchSize': 12},
      ),
      createdAt: DateTime.utc(2026, 1, created),
      updatedAt: DateTime.utc(2026, 1, updated ?? created),
    );

    test('latest success excludes history even updated more recently', () {
      final jobs = [
        photo('old', TaskState.failed, 1, updated: 9),
        photo('latest', TaskState.succeeded, 3),
        photo('latest', TaskState.succeeded, 4),
      ];
      for (final records in [jobs, jobs.reversed.toList()]) {
        final status = PhotoQueueStatus.fromJobs(
          records,
          PhotoQueuePhase.completed,
        );
        expect(status.total, 2);
        expect(status.completed, 2);
        expect(status.failed, 0);
        expect(status.body, isNot(contains('failed')));
      }
    });

    for (final pending in [
      TaskState.queued,
      TaskState.running,
      TaskState.retried,
    ]) {
      test('${pending.name} batch is not hidden by newer finished work', () {
        final status = PhotoQueueStatus.fromJobs([
          photo('history', TaskState.failed, 1, updated: 10),
          photo('newer-finished', TaskState.succeeded, 8),
          photo('active', pending, 3),
          photo('active', TaskState.succeeded, 4),
        ], PhotoQueuePhase.processing);
        expect(status.total, 2);
        expect(status.completed, 1);
        expect(status.failed, 0);
      });
    }

    test('newest pending batch uses first creation, not last publication', () {
      final status = PhotoQueueStatus.fromJobs([
        photo('older', TaskState.queued, 1),
        photo('older', TaskState.failed, 7),
        photo('newer', TaskState.queued, 3),
      ], PhotoQueuePhase.queued);
      expect(status.total, 1);
      expect(status.completed, 0);
      expect(status.failed, 0);
    });

    test('equal creation timestamps have an order-independent tie break', () {
      final jobs = [
        photo('a', TaskState.failed, 1),
        photo('b', TaskState.succeeded, 1),
      ];
      for (final records in [jobs, jobs.reversed.toList()]) {
        final status = PhotoQueueStatus.fromJobs(
          records,
          PhotoQueuePhase.completed,
        );
        expect(status.total, 1);
        expect(status.completed, 1);
        expect(status.failed, 0);
      }
    });

    test('empty records produce zero counts', () {
      final status = PhotoQueueStatus.fromJobs([], PhotoQueuePhase.completed);
      expect(status.total, 0);
      expect(status.completed, 0);
      expect(status.failed, 0);
    });
  });

  test('counts durable records, excluding planned and unrelated tasks', () {
    final now = DateTime.now();
    final jobs = [
      for (final state in TaskState.values)
        TaskStatusRecord(
          status: TaskStatus(
            id: state.name,
            state: state,
            attempt: 0,
            meta: {'batchId': 'batch', 'batchSize': 12},
          ),
          createdAt: now,
          updatedAt: now,
        ),
      TaskStatusRecord(
        status: TaskStatus(id: 'other', state: TaskState.succeeded, attempt: 0),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final status = PhotoQueueStatus.fromJobs(jobs, PhotoQueuePhase.processing);
    expect(status.total, TaskState.values.length);
    expect(status.completed, 3);
    expect(status.failed, 2);
    for (final phase in PhotoQueuePhase.values) {
      expect(
        status.withPhase(phase).ongoing,
        phase == PhotoQueuePhase.processing,
      );
      expect(status.withPhase(phase).completed, 3);
    }
  });

  test('optional plugin failures are contained', () async {
    final notifications = AndroidStatusNotifications(
      show: (_) async => throw StateError('permission denied'),
      cancel: () async => throw StateError('plugin unavailable'),
    );
    await notifications.show(
      const PhotoQueueStatus(phase: PhotoQueuePhase.queued),
    );
    await notifications.cancel();
  });

  for (final reason in WorkerRunStopReason.values) {
    test(
      'observer finishes ${reason.name} without leaving ongoing status',
      () async {
        final app = await StemApp.create(
          tasks: const [],
          broker: StemBrokerFactory.inMemory(),
          backend: StemBackendFactory.inMemory(),
        );
        addTearDown(app.close);
        await app.backend.set(
          'photo',
          TaskState.queued,
          attempt: 0,
          meta: {'queue': queueName, 'batchId': 'batch', 'batchSize': 12},
        );
        final shown = <PhotoQueueStatus>[];
        var cancelled = 0;
        final notifications = AndroidStatusNotifications(
          show: (status) async => shown.add(status),
          cancel: () async {
            cancelled++;
          },
        );
        final observer = PhotoQueueNotificationObserver(app, notifications);
        await observer.start();
        await observer.finish(
          WorkerRunOutcome(
            reason: reason,
            deliveriesProcessed: 0,
            elapsed: Duration.zero,
          ),
        );
        if (reason == WorkerRunStopReason.cancelled) {
          expect(cancelled, 1);
        } else {
          expect(shown.last.ongoing, isFalse);
          expect(shown.last.phase, switch (reason) {
            WorkerRunStopReason.budgetExceeded => PhotoQueuePhase.budgetWaiting,
            WorkerRunStopReason.failed => PhotoQueuePhase.error,
            _ => PhotoQueuePhase.waiting,
          });
        }
        expect(shown.first.total, 1);
        expect(shown.first.completed, 0);
      },
    );
  }
}

class _EventWorker implements Worker {
  _EventWorker(this.workerId);

  @override
  final String workerId;
  final controller = StreamController<WorkerEvent>.broadcast();

  @override
  Stream<WorkerEvent> get events => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
