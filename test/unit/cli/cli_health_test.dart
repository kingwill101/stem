import 'package:stem/src/cli/cli_runner.dart';
import 'package:test/test.dart';

void main() {
  test('health command reports missing broker configuration', () async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final exitCode = await runStemCli(
      ['health'],
      out: stdoutBuffer,
      err: stderrBuffer,
      environment: const {},
    );

    expect(exitCode, 64);
    expect(stderrBuffer.toString(), contains('STEM_BROKER_URL'));
  });

  test('health command surfaces connection failures', () async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final exitCode = await runStemCli(
      ['health'],
      out: stdoutBuffer,
      err: stderrBuffer,
      environment: const {
        'STEM_BROKER_URL': 'redis://127.0.0.1:64000',
        'STEM_RESULT_BACKEND_URL': '',
      },
    );

    expect(exitCode, 70);
    expect(stdoutBuffer.toString(), contains('broker'));
    expect(stdoutBuffer.toString(), contains('Connection failed'));
  });

  test('health command supports postgres brokers', () async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final exitCode = await runStemCli(
      ['health'],
      out: stdoutBuffer,
      err: stderrBuffer,
      environment: const {
        'STEM_BROKER_URL': 'postgres://127.0.0.1:65432/stem',
        'STEM_RESULT_BACKEND_URL': '',
      },
    );

    expect(exitCode, 70);
    expect(stdoutBuffer.toString(), contains('broker'));
    expect(stdoutBuffer.toString(), contains('Connection failed'));
  });
}
