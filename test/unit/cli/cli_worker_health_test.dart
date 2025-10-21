import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';

void main() {
  group('worker healthcheck', () {
    late Directory tempDir;
    Process? stubProcess;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-health');
    });

    tearDown(() async {
      if (stubProcess != null) {
        stubProcess!.kill(ProcessSignal.sigterm);
        await stubProcess!.exitCode
            .timeout(const Duration(seconds: 5), onTimeout: () => 0);
        stubProcess = null;
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reports ok when pid is alive', () async {
      final pidFile = p.join(tempDir.path, 'alpha.pid');
      final script = p.absolute('test/support/fixtures/daemon_stub.dart');
      stubProcess = await Process.start(
        Platform.resolvedExecutable,
        ['--disable-dart-dev', script],
      );
      File(pidFile).writeAsStringSync('${stubProcess!.pid}\n');

      final out = StringBuffer();
      final code = await runStemCli(
        [
          'worker',
          'healthcheck',
          '--node',
          'alpha',
          '--pidfile',
          pidFile,
          '--json',
        ],
        out: out,
        err: StringBuffer(),
        environment: Platform.environment,
      );

      expect(code, 0, reason: out.toString());
      final payload = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(payload['status'], 'ok');
      expect(payload['pid'], stubProcess!.pid);
      expect(payload['uptimeSeconds'], isA<num>());
    });

    test('reports error when pidfile missing', () async {
      final pidFile = p.join(tempDir.path, 'missing.pid');
      final out = StringBuffer();
      final code = await runStemCli(
        [
          'worker',
          'healthcheck',
          '--pidfile',
          pidFile,
        ],
        out: out,
        err: StringBuffer(),
        environment: Platform.environment,
      );

      expect(code, isNot(equals(0)));
      expect(out.toString().toLowerCase(), contains('unhealthy'));
    });
  });

  group('worker diagnose', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-diagnose');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('flags missing log directory', () async {
      final pidDir = Directory(p.join(tempDir.path, 'run', 'stem'))
        ..createSync(recursive: true);
      final pidFile = p.join(pidDir.path, 'alpha.pid');
      File(pidFile).writeAsStringSync('99999\n');

      final missingLog =
          p.join(tempDir.path, 'var', 'log', 'stem', 'alpha.log');

      final out = StringBuffer();
      final code = await runStemCli(
        [
          'worker',
          'diagnose',
          '--pidfile',
          pidFile,
          '--logfile',
          missingLog,
        ],
        out: out,
        err: StringBuffer(),
        environment: Platform.environment,
      );

      expect(code, isNot(equals(0)));
      expect(out.toString(), contains('Log directory exists'));
      expect(out.toString().toLowerCase(), contains('missing'));
    });
  });
}
