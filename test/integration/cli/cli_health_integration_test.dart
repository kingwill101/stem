import 'dart:io';

import 'package:stem/src/cli/cli_runner.dart';
import 'package:test/test.dart';

void main() {
  const redisUrl = 'redis://127.0.0.1:56379';
  const postgresUrl = 'postgres://postgres:postgres@127.0.0.1:65432/stem_test';

  Future<void> ensureServicesAvailable() async {
    final redisAvailable = await _canConnect('127.0.0.1', 56379);
    final postgresAvailable = await _canConnect('127.0.0.1', 65432);
    if (!redisAvailable || !postgresAvailable) {
      fail(
        'Docker test services are not reachable on 127.0.0.1:56379/65432. '
        'Start docker/testing/docker-compose.yml before running integration tests.',
      );
    }
  }

  test('stem health succeeds against docker stack', () async {
    await ensureServicesAvailable();

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final exitCode = await runStemCli(
      ['health'],
      out: stdoutBuffer,
      err: stderrBuffer,
      environment: const {
        'STEM_BROKER_URL': redisUrl,
        'STEM_RESULT_BACKEND_URL': postgresUrl,
      },
    );

    expect(exitCode, 0);
    final output = stdoutBuffer.toString();
    expect(output, contains('[ok'));
    expect(output, contains('broker: Connected to $redisUrl'));
    expect(output, contains('backend: Connected to $postgresUrl'));
    expect(stderrBuffer.isEmpty, isTrue);
  });
}

Future<bool> _canConnect(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
