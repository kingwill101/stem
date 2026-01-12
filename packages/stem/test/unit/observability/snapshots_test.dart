import 'dart:io';

import 'package:stem/src/observability/snapshots.dart';
import 'package:test/test.dart';

void main() {
  group('ObservabilityReport', () {
    late Directory tempDir;
    late File reportFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-report-');
      reportFile = File('${tempDir.path}/report.json');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fromFile returns empty report when missing or empty', () {
      final missing = ObservabilityReport.fromFile(reportFile.path);
      expect(missing.queues, isEmpty);
      expect(missing.workers, isEmpty);
      expect(missing.dlq, isEmpty);

      reportFile.writeAsStringSync('   ');
      final empty = ObservabilityReport.fromFile(reportFile.path);
      expect(empty.queues, isEmpty);
      expect(empty.workers, isEmpty);
      expect(empty.dlq, isEmpty);
    });

    test('round trips through json', () {
      final report = ObservabilityReport(
        queues: [
          QueueSnapshot(queue: 'default', pending: 3, inflight: 1),
        ],
        workers: [
          WorkerSnapshot(
            id: 'worker-1',
            active: 2,
            lastHeartbeat: DateTime.utc(2025, 1, 2, 3, 4, 5),
          ),
        ],
        dlq: [
          DlqEntrySnapshot(
            queue: 'default',
            taskId: 'task-9',
            reason: 'failed',
            deadAt: DateTime.utc(2025, 1, 2, 5, 6, 7),
          ),
        ],
      );

      final decoded = ObservabilityReport.fromJson(report.toJson());

      expect(decoded.queues.single.queue, equals('default'));
      expect(decoded.queues.single.pending, equals(3));
      expect(decoded.workers.single.id, equals('worker-1'));
      expect(decoded.dlq.single.taskId, equals('task-9'));
    });
  });
}
