import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';

String _daemonStubPath() {
  final cwd = Directory.current.path;
  final local = p.join(cwd, 'test', 'support', 'fixtures', 'daemon_stub.dart');
  if (File(local).existsSync()) {
    return local;
  }
  final workspace = p.join(
    cwd,
    'packages',
    'stem_cli',
    'test',
    'support',
    'fixtures',
    'daemon_stub.dart',
  );
  if (File(workspace).existsSync()) {
    return workspace;
  }
  return p.normalize(
    p.join(
      p.dirname(Platform.script.toFilePath()),
      '..',
      '..',
      'support',
      'fixtures',
      'daemon_stub.dart',
    ),
  );
}

Future<Process> _startHealthcheckStub() async {
  if (Platform.isWindows) {
    final script = _daemonStubPath();
    return Process.start(Platform.resolvedExecutable, [
      '--disable-dart-dev',
      script,
    ]);
  }
  return Process.start('sleep', ['30']);
}

void main() {
  group('worker healthcheck', () {
    late Directory tempDir;
    Process? stubProcess;

    Future<void> _waitForPid(int pid) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        final running = Platform.isWindows
            ? Process.killPid(pid)
            : Platform.isLinux
            ? Directory('/proc/$pid').existsSync()
            : (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;
        if (running) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError('Timed out waiting for worker PID $pid to be running.');
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-health');
    });

    tearDown(() async {
      if (stubProcess != null) {
        stubProcess!.kill(ProcessSignal.sigterm);
        await stubProcess!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => 0,
        );
        stubProcess = null;
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reports ok when pid is alive', () async {
      final pidFile = p.join(tempDir.path, 'alpha.pid');
      stubProcess = await _startHealthcheckStub();
      final exited = await stubProcess!.exitCode.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => -1,
      );
      if (exited != -1) {
        throw StateError('Healthcheck stub exited early with code $exited.');
      }
      await _waitForPid(stubProcess!.pid);
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
        ['worker', 'healthcheck', '--pidfile', pidFile],
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

      final missingLog = p.join(
        tempDir.path,
        'var',
        'log',
        'stem',
        'alpha.log',
      );

      final out = StringBuffer();
      final code = await runStemCli(
        ['worker', 'diagnose', '--pidfile', pidFile, '--logfile', missingLog],
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
