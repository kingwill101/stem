import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';

void main() {
  test('workerDetailPreview returns the first trimmed line', () {
    final snapshot = StemFlutterQueueSnapshot(
      workerStatus: StemFlutterWorkerStatus.running,
      workerDetail: '  Worker healthy  \nsecond line',
      jobs: <StemFlutterTrackedJob>[
        StemFlutterTrackedJob(
          taskId: 'job-1',
          label: 'Job 1',
          state: TaskState.succeeded,
          updatedAt: DateTime.utc(2026, 4, 20, 12),
        ),
      ],
    );

    expect(snapshot.workerDetailPreview, 'Worker healthy');
  });

  test('copyWith can clear the worker detail', () {
    const snapshot = StemFlutterQueueSnapshot(
      workerStatus: StemFlutterWorkerStatus.waiting,
      workerDetail: 'Last heartbeat 12:00:00',
    );

    final updated = snapshot.copyWith(
      workerStatus: StemFlutterWorkerStatus.running,
      clearWorkerDetail: true,
    );

    expect(updated.workerStatus, StemFlutterWorkerStatus.running);
    expect(updated.workerDetail, isNull);
  });
}
