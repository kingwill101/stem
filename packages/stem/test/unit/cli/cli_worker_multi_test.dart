import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';

void main() {
  group('worker multi', () {
    late Directory tempDir;
    late String pidTemplate;
    late String logTemplate;
    late String envFilePath;
    late Map<String, String> baseEnvironment;

    Future<void> expectLogNotEmpty(String node) async {
      final file = File(logTemplate.replaceAll('%n', node));
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (file.existsSync() && file.lengthSync() == 0) {
        if (DateTime.now().isAfter(deadline)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-worker-multi');
      pidTemplate = p.join(tempDir.path, '%n.pid');
      logTemplate = p.join(tempDir.path, '%n.log');
      envFilePath = p.join(tempDir.path, 'stem.env');

      final scriptPath = p.absolute('test/support/fixtures/daemon_stub.dart');
      final commandLine =
          '${Platform.resolvedExecutable} --disable-dart-dev "${scriptPath.replaceAll('"', '\\"')}"';

      File(
        envFilePath,
      ).writeAsStringSync('STEM_WORKER_COMMAND="$commandLine"\n');

      baseEnvironment = Map<String, String>.from(Platform.environment)
        ..['PATH'] = Platform.environment['PATH'] ?? ''
        ..['STEM_BROKER_URL'] = 'memory://'
        ..['STEM_RESULT_BACKEND_URL'] = 'memory://';

      addTearDown(() async {
        await runStemCli(
          [
            'worker',
            'multi',
            'stop',
            'alpha',
            'beta',
            '--pidfile',
            pidTemplate,
            '--env-file',
            envFilePath,
          ],
          out: StringBuffer(),
          err: StringBuffer(),
          environment: baseEnvironment,
        );
      });
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'start, status, and stop worker nodes',
      () async {
        final startOut = StringBuffer();
        final startErr = StringBuffer();
        final startCode = await runStemCli(
          [
            'worker',
            'multi',
            'start',
            'alpha',
            'beta',
            '--pidfile',
            pidTemplate,
            '--logfile',
            logTemplate,
            '--env-file',
            envFilePath,
          ],
          out: startOut,
          err: startErr,
          environment: baseEnvironment,
        );

        expect(startCode, 0, reason: startErr.toString());
        expect(
          File(pidTemplate.replaceAll('%n', 'alpha')).existsSync(),
          isTrue,
        );
        expect(File(pidTemplate.replaceAll('%n', 'beta')).existsSync(), isTrue);
        await expectLogNotEmpty('alpha');
        await expectLogNotEmpty('beta');

        final statusOut = StringBuffer();
        final statusCode = await runStemCli(
          [
            'worker',
            'multi',
            'status',
            'alpha',
            'beta',
            '--pidfile',
            pidTemplate,
            '--env-file',
            envFilePath,
          ],
          out: statusOut,
          err: StringBuffer(),
          environment: baseEnvironment,
        );

        expect(statusCode, 0, reason: statusOut.toString());
        expect(statusOut.toString(), contains('alpha: running'));
        expect(statusOut.toString(), contains('beta: running'));

        final stopOut = StringBuffer();
        final stopCode = await runStemCli(
          [
            'worker',
            'multi',
            'stop',
            'alpha',
            'beta',
            '--pidfile',
            pidTemplate,
            '--env-file',
            envFilePath,
          ],
          out: stopOut,
          err: StringBuffer(),
          environment: baseEnvironment,
        );

        expect(stopCode, 0, reason: stopOut.toString());
        expect(
          File(pidTemplate.replaceAll('%n', 'alpha')).existsSync(),
          isFalse,
        );
        expect(
          File(pidTemplate.replaceAll('%n', 'beta')).existsSync(),
          isFalse,
        );

        // Status after stopping should report not running.
        // Allow some time for background processes to terminate gracefully.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
