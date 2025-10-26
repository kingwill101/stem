import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/file_schedule_repository.dart';
import 'package:stem_cli/src/cli/schedule.dart' show ScheduleCliContext;

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

    test(
      'apply retries on conflict when schedule store updates concurrently',
      () async {
        final baseStore = InMemoryScheduleStore();
        final flakyStore = FlakyScheduleStore(
          baseStore,
          failuresBeforeSuccess: 1,
        );

        final now = DateTime.now().toUtc();
        await baseStore.upsert(
          ScheduleEntry(
            id: 'nightly',
            taskName: 'noop',
            queue: 'default',
            spec: IntervalScheduleSpec(every: const Duration(minutes: 5)),
          ),
        );
        await baseStore.markExecuted(
          'nightly',
          scheduledFor: now.subtract(const Duration(minutes: 5)),
          executedAt: now.subtract(const Duration(minutes: 4, seconds: 30)),
        );

        final defs = File('${tempDir.path}/conflict_defs.json')
          ..writeAsStringSync(
            jsonEncode([
              {
                'id': 'nightly',
                'task': 'noop',
                'queue': 'priority',
                'schedule': 'every:30s',
              },
            ]),
          );

        final code = await runStemCli(
          ['schedule', 'apply', '--file', defs.path, '--yes'],
          scheduleContextBuilder: () async =>
              ScheduleCliContext.store(storeInstance: flakyStore),
        );
        expect(code, equals(0));

        final updated = await baseStore.get('nightly');
        expect(updated, isNotNull);
        expect(updated!.queue, equals('priority'));
        expect(
          updated.spec,
          isA<IntervalScheduleSpec>().having(
            (spec) => spec.every,
            'every',
            equals(const Duration(seconds: 30)),
          ),
        );
        expect(updated.lastRunAt, isNotNull);
        expect(updated.totalRunCount, greaterThan(0));
        expect(flakyStore.conflictAttempts, equals(1));
      },
    );

    test('enable retries on conflict when toggling schedule state', () async {
      final baseStore = InMemoryScheduleStore();
      final flakyStore = FlakyScheduleStore(
        baseStore,
        failuresBeforeSuccess: 1,
      );

      await baseStore.upsert(
        ScheduleEntry(
          id: 'nightly',
          taskName: 'noop',
          queue: 'default',
          enabled: false,
          spec: IntervalScheduleSpec(every: const Duration(minutes: 5)),
        ),
      );

      final code = await runStemCli(
        ['schedule', 'enable', 'nightly'],
        scheduleContextBuilder: () async =>
            ScheduleCliContext.store(storeInstance: flakyStore),
      );
      expect(code, equals(0));

      final updated = await baseStore.get('nightly');
      expect(updated, isNotNull);
      expect(updated!.enabled, isTrue);
      expect(flakyStore.conflictAttempts, equals(1));
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

    test('schedule enable toggles entry on file repo', () async {
      final filePath = '${tempDir.path}/enable.json';
      final repo = FileScheduleRepository(path: filePath);
      await repo.save([
        ScheduleEntry(
          id: 'nightly',
          taskName: 'cleanup',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(minutes: 5)),
          enabled: false,
        ),
      ]);

      final out = StringBuffer();
      final code = await runStemCli(
        ['schedule', 'enable', 'nightly'],
        out: out,
        scheduleFilePath: filePath,
      );

      expect(code, equals(0));
      expect(out.toString(), contains('Enabled schedule'));

      final reloaded = await repo.load();
      expect(reloaded.single.enabled, isTrue);
    });

    test('schedule disable toggles entry on file repo', () async {
      final filePath = '${tempDir.path}/disable.json';
      final repo = FileScheduleRepository(path: filePath);
      await repo.save([
        ScheduleEntry(
          id: 'nightly',
          taskName: 'cleanup',
          queue: 'default',
          spec: IntervalScheduleSpec(every: const Duration(minutes: 5)),
          enabled: true,
        ),
      ]);

      final out = StringBuffer();
      final code = await runStemCli(
        ['schedule', 'disable', 'nightly'],
        out: out,
        scheduleFilePath: filePath,
      );

      expect(code, equals(0));
      expect(out.toString(), contains('Disabled schedule'));

      final reloaded = await repo.load();
      expect(reloaded.single.enabled, isFalse);
    });
  });
}

class FlakyScheduleStore implements ScheduleStore {
  FlakyScheduleStore(this.delegate, {this.failuresBeforeSuccess = 1});

  final ScheduleStore delegate;
  int failuresBeforeSuccess;
  int conflictAttempts = 0;

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) =>
      delegate.due(now, limit: limit);

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess -= 1;
      conflictAttempts += 1;
      final current = await delegate.get(entry.id);
      if (current != null) {
        await delegate.upsert(current);
        final latest = await delegate.get(entry.id);
        throw ScheduleConflictException(
          entry.id,
          expectedVersion: entry.version,
          actualVersion: latest?.version ?? entry.version,
        );
      }
      throw ScheduleConflictException(
        entry.id,
        expectedVersion: entry.version,
        actualVersion: entry.version + 1,
      );
    }
    await delegate.upsert(entry);
  }

  @override
  Future<void> remove(String id) => delegate.remove(id);

  @override
  Future<List<ScheduleEntry>> list({int? limit}) => delegate.list(limit: limit);

  @override
  Future<ScheduleEntry?> get(String id) => delegate.get(id);

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
  }) => delegate.markExecuted(
    id,
    scheduledFor: scheduledFor,
    executedAt: executedAt,
    jitter: jitter,
    lastError: lastError,
    success: success,
    runDuration: runDuration,
    nextRunAt: nextRunAt,
    drift: drift,
  );
}
