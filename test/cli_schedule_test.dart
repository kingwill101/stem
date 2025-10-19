import 'dart:io';

import 'package:test/test.dart';
import 'package:untitled6/src/cli/cli_runner.dart';
import 'package:untitled6/src/cli/file_schedule_repository.dart';

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

    test('add and list schedules', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      var code = await runStemCli(
        [
          'schedule',
          'add',
          '--id',
          'cleanup',
          '--task',
          'noop',
          '--spec',
          'every:1m',
        ],
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

    test('remove deletes schedule', () async {
      await runStemCli([
        'schedule',
        'add',
        '--id',
        'cleanup',
        '--task',
        'noop',
        '--spec',
        'every:1m',
      ], scheduleFilePath: scheduleFile);

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['schedule', 'remove', '--id', 'cleanup'],
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
}
