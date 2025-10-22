import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/cli/file_schedule_repository.dart';
import 'package:stem/src/observability/snapshots.dart';
import 'package:stem/stem.dart';

void main() {
  group('schedule CLI', () {
    late Directory tempDir;
    late String scheduleFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem_cli_test');
      scheduleFile = '${tempDir.path}/schedules.json';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('apply and list schedules', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final defs = File('${tempDir.path}/definitions.json')
        ..writeAsStringSync(
          jsonEncode([
            {'id': 'cleanup', 'task': 'noop', 'schedule': 'every:1m'},
          ]),
        );

      var code = await runStemCli(
        ['schedule', 'apply', '--file', defs.path, '--yes'],
        out: out,
        err: err,
        scheduleFilePath: scheduleFile,
      );
      expect(code, equals(0));
      expect(err.isEmpty, isTrue);

      final repo = FileScheduleRepository(path: scheduleFile);
      final entries = await repo.load();
      expect(entries, hasLength(1));
      expect(entries.first.id, 'cleanup');

      final listOut = StringBuffer();
      code = await runStemCli(
        ['schedule', 'list'],
        out: listOut,
        err: err,
        scheduleFilePath: scheduleFile,
      );
      expect(code, equals(0));
      expect(listOut.toString(), contains('cleanup'));
    });

    test('dry run prints future timestamps', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['schedule', 'dry-run', '--spec', 'every:1m', '--count', '3'],
        out: out,
        err: err,
        scheduleFilePath: scheduleFile,
      );
      expect(code, equals(0));
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(3));
    });

    test('delete removes schedule', () async {
      final defs = File('${tempDir.path}/definitions.json')
        ..writeAsStringSync(
          jsonEncode([
            {'id': 'cleanup', 'task': 'noop', 'schedule': 'every:1m'},
          ]),
        );

      await runStemCli([
        'schedule',
        'apply',
        '--file',
        defs.path,
        '--yes',
      ], scheduleFilePath: scheduleFile);

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['schedule', 'delete', '--id', 'cleanup', '--yes'],
        out: out,
        err: err,
        scheduleFilePath: scheduleFile,
      );
      expect(code, equals(0));

      final repo = FileScheduleRepository(path: scheduleFile);
      final entries = await repo.load();
      expect(entries, isEmpty);
    });
  });

  group('observe CLI', () {
    late Directory tempDir;
    late String snapshotFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem_observe_cli_test');
      snapshotFile = '${tempDir.path}/snapshot.json';
      StemMetrics.instance.reset();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('metrics prints JSON snapshot', () async {
      StemMetrics.instance.reset();
      StemMetrics.instance.increment(
        'stem.tasks.succeeded',
        tags: {'task': 'demo'},
      );

      final out = StringBuffer();
      final code = await runStemCli(['observe', 'metrics'], out: out);
      expect(code, equals(0));
      expect(out.toString(), contains('stem.tasks.succeeded'));
    });

    test('queues prints table from snapshot', () async {
      final report = ObservabilityReport(
        queues: [QueueSnapshot(queue: 'default', pending: 3, inflight: 1)],
      );
      File(snapshotFile).writeAsStringSync(jsonEncode(report.toJson()));

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['observe', 'queues', '--file', snapshotFile],
        out: out,
        err: err,
      );
      expect(code, equals(0));
      expect(out.toString(), contains('default'));
    });

    test('workers prints table from snapshot', () async {
      final report = ObservabilityReport(
        workers: [
          WorkerSnapshot(
            id: 'worker-1',
            active: 2,
            lastHeartbeat: DateTime.utc(2024, 1, 1),
          ),
        ],
      );
      File(snapshotFile).writeAsStringSync(jsonEncode(report.toJson()));

      final out = StringBuffer();
      final code = await runStemCli([
        'observe',
        'workers',
        '--file',
        snapshotFile,
      ], out: out);
      expect(code, equals(0));
      expect(out.toString(), contains('worker-1'));
    });

    test('dlq prints entries from snapshot', () async {
      final report = ObservabilityReport(
        dlq: [
          DlqEntrySnapshot(
            queue: 'default',
            taskId: 'task-123',
            reason: 'error',
            deadAt: DateTime.utc(2024, 1, 1),
          ),
        ],
      );
      File(snapshotFile).writeAsStringSync(jsonEncode(report.toJson()));

      final out = StringBuffer();
      final code = await runStemCli([
        'observe',
        'dlq',
        '--file',
        snapshotFile,
      ], out: out);
      expect(code, equals(0));
      expect(out.toString(), contains('task-123'));
    });

    test('schedules prints next runs', () async {
      final repo = FileScheduleRepository(path: snapshotFile);
      await repo.save([
        ScheduleEntry(
          id: 'nightly',
          taskName: 'cleanup',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(minutes: 1)),
        ),
      ]);

      final out = StringBuffer();
      final code = await runStemCli([
        'observe',
        'schedules',
        '--file',
        snapshotFile,
      ], out: out);
      expect(code, equals(0));
      expect(out.toString(), contains('nightly'));
    });
  });
}
