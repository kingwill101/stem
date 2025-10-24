import 'dart:io';

import 'package:stem/src/observability/heartbeat.dart';
import 'package:stem/src/observability/heartbeat_transport.dart';
import 'package:stem/src/security/tls.dart';
import 'package:test/test.dart';

void main() {
  const namespace = 'integration-heartbeat';
  const redisUrl = 'redis://127.0.0.1:56379';
  const redissUrl = 'rediss://127.0.0.1:56379';

  Future<void> ensureRedisAvailable() async {
    final available = await _canConnect('127.0.0.1', 56379);
    if (!available) {
      fail(
        'Redis test service is not reachable on 127.0.0.1:56379. '
        'Start docker/testing/docker-compose.yml before running integration tests.',
      );
    }
  }

  test('heartbeat transport publishes without TLS', () async {
    await ensureRedisAvailable();

    final transport = await RedisHeartbeatTransport.connect(
      redisUrl,
      namespace: namespace,
    );
    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      timestamp: DateTime.now().toUtc(),
      isolateCount: 1,
      inflight: 0,
      queues: const [],
    );

    await transport.publish(heartbeat);
    await transport.close();
  });

  test('heartbeat transport logs TLS handshake failures', () async {
    await ensureRedisAvailable();

    await expectLater(
      RedisHeartbeatTransport.connect(
        redissUrl,
        namespace: namespace,
        tls: const TlsConfig(),
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<Exception>()),
    );
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
