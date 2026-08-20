import 'dart:io';

import 'package:stem_cli/stem_cli.dart';
import 'package:test/test.dart';

void main() {
  const redisUrl = 'redis://127.0.0.1:56379';
  const postgresUrl = 'postgres://postgres:postgres@127.0.0.1:65432/stem_test';

  Future<bool> ensureServicesAvailable() async {
    final redisAvailable = await _canConnect('127.0.0.1', 56379);
    final postgresAvailable = await _canConnect('127.0.0.1', 65432);
    return redisAvailable && postgresAvailable;
  }

  final servicesAvailable = ensureServicesAvailable();

  test('stem health succeeds against docker stack', () async {
    if (!await servicesAvailable) {
      return;
    }
    // Postgres adapters resolve ormed.yaml relative to cwd; point at the
    // package config so health checks can open connections.
    final originalDir = Directory.current;
    final postgresDir = _findPostgresPackageDirectory();
    Directory.current = postgresDir;
    addTearDown(() {
      Directory.current = originalDir;
    });

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
    final output = stdoutBuffer.toString().toLowerCase();
    expect(output, contains('health checks'));
    expect(output, contains('broker: connected to ${redisUrl.toLowerCase()}'));
    expect(
      output,
      contains('backend: connected to ${postgresUrl.toLowerCase()}'),
    );
    expect(stderrBuffer.isEmpty, isTrue);
  });
}

Directory _findPostgresPackageDirectory() {
  final candidates = [
    Directory('../stem_postgres'),
    Directory('../packages/stem_postgres'),
    Directory('packages/stem_postgres'),
  ];
  for (final candidate in candidates) {
    final absolute = candidate.absolute;
    if (absolute.existsSync()) return absolute;
  }
  throw StateError(
    'Could not locate packages/stem_postgres from ${Directory.current.path}.',
  );
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
