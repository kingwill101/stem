import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';

class _FakeBroker implements Broker {
  _FakeBroker({
    required this.pendingCountValue,
    required this.inflightCountValue,
  });

  final int? pendingCountValue;
  final int? inflightCountValue;

  @override
  Future<int?> pendingCount(String queue) async => pendingCountValue;

  @override
  Future<int?> inflightCount(String queue) async => inflightCountValue;

  @override
  bool get supportsDelayed => false;

  @override
  bool get supportsPriority => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResultBackend implements ResultBackend {
  _FakeResultBackend({required this.page, required this.heartbeats});

  TaskStatusPage page;
  List<WorkerHeartbeat> heartbeats;

  @override
  Future<TaskStatusPage> listTaskStatuses(TaskStatusListRequest request) async {
    return page;
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async => heartbeats;

  @override
  Stream<TaskStatus> watch(String taskId) => const Stream<TaskStatus>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StemFlutterQueueMonitor', () {
    test('refresh maps jobs and marks fresh heartbeats as running', () async {
      final backend = _FakeResultBackend(
        page: TaskStatusPage(
          items: <TaskStatusRecord>[
            TaskStatusRecord(
              status: TaskStatus(
                id: 'job-older',
                state: TaskState.failed,
                attempt: 1,
                error: const TaskError(type: 'StateError', message: 'boom'),
              ),
              createdAt: DateTime.utc(2026, 4, 20, 12),
              updatedAt: DateTime.utc(2026, 4, 20, 12, 0, 1),
            ),
            TaskStatusRecord(
              status: TaskStatus(
                id: 'job-newer',
                state: TaskState.succeeded,
                attempt: 1,
                payload: 'done',
                meta: const <String, Object?>{'label': 'Thumbnail job'},
              ),
              createdAt: DateTime.utc(2026, 4, 20, 12),
              updatedAt: DateTime.utc(2026, 4, 20, 12, 0, 2),
            ),
          ],
        ),
        heartbeats: <WorkerHeartbeat>[
          WorkerHeartbeat(
            workerId: 'worker-a',
            timestamp: DateTime.now().toUtc().subtract(
              const Duration(milliseconds: 200),
            ),
            isolateCount: 1,
            inflight: 1,
            queues: <QueueHeartbeat>[QueueHeartbeat(name: 'jobs', inflight: 1)],
          ),
        ],
      );
      final monitor = StemFlutterQueueMonitor(
        backend: backend,
        broker: _FakeBroker(pendingCountValue: 3, inflightCountValue: 1),
        queueName: 'jobs',
        workerId: 'worker-a',
        heartbeatInterval: const Duration(seconds: 1),
      );
      addTearDown(monitor.dispose);

      await monitor.refresh();

      expect(monitor.snapshot.workerStatus, StemFlutterWorkerStatus.running);
      expect(monitor.snapshot.pendingCount, 3);
      expect(monitor.snapshot.inflightCount, 1);
      expect(
        monitor.snapshot.workerDetailPreview,
        matches(RegExp(r'^Heartbeat \d{2}:\d{2}:\d{2}$')),
      );
      expect(
        monitor.snapshot.jobs.map((job) => job.taskId),
        orderedEquals(<String>['job-newer', 'job-older']),
      );
      expect(monitor.snapshot.jobs.first.label, 'Thumbnail job');
      expect(monitor.snapshot.jobs.first.result, 'done');
      expect(monitor.snapshot.jobs.last.errorMessage, 'boom');
    });

    test('refresh marks stale heartbeats as waiting', () async {
      final backend = _FakeResultBackend(
        page: const TaskStatusPage(items: <TaskStatusRecord>[]),
        heartbeats: <WorkerHeartbeat>[
          WorkerHeartbeat(
            workerId: 'worker-a',
            timestamp: DateTime.now().toUtc().subtract(
              const Duration(seconds: 5),
            ),
            isolateCount: 1,
            inflight: 0,
            queues: const <QueueHeartbeat>[],
          ),
        ],
      );
      final monitor = StemFlutterQueueMonitor(
        backend: backend,
        broker: _FakeBroker(pendingCountValue: 0, inflightCountValue: 0),
        queueName: 'jobs',
        workerId: 'worker-a',
        heartbeatInterval: const Duration(seconds: 1),
      );
      addTearDown(monitor.dispose);

      await monitor.refresh();

      expect(monitor.snapshot.workerStatus, StemFlutterWorkerStatus.waiting);
      expect(
        monitor.snapshot.workerDetailPreview,
        startsWith('Last heartbeat '),
      );
    });

    test('fatal worker signals are preserved across refreshes', () async {
      final backend = _FakeResultBackend(
        page: const TaskStatusPage(items: <TaskStatusRecord>[]),
        heartbeats: <WorkerHeartbeat>[
          WorkerHeartbeat(
            workerId: 'worker-a',
            timestamp: DateTime.now().toUtc().subtract(
              const Duration(milliseconds: 200),
            ),
            isolateCount: 1,
            inflight: 0,
            queues: const <QueueHeartbeat>[],
          ),
        ],
      );
      final monitor = StemFlutterQueueMonitor(
        backend: backend,
        broker: _FakeBroker(pendingCountValue: 0, inflightCountValue: 0),
        queueName: 'jobs',
        workerId: 'worker-a',
        heartbeatInterval: const Duration(seconds: 1),
      );
      final signals = StreamController<StemFlutterWorkerSignal>();
      addTearDown(() async {
        await signals.close();
        await monitor.dispose();
      });

      monitor.bindWorkerSignals(signals.stream);
      signals.add(const StemFlutterWorkerSignal.fatal('database locked'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(monitor.snapshot.workerStatus, StemFlutterWorkerStatus.error);
      expect(monitor.snapshot.workerDetail, 'database locked');

      await monitor.refresh();

      expect(monitor.snapshot.workerStatus, StemFlutterWorkerStatus.error);
      expect(monitor.snapshot.workerDetail, 'database locked');
    });
  });
}
