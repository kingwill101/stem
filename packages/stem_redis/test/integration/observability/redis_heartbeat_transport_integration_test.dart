import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

void main() {
  const namespace = 'integration-heartbeat';
  const redisUrl = 'redis://127.0.0.1:56379';
  const redissUrl = 'rediss://127.0.0.1:56379';
  final tlsUrl = Platform.environment['STEM_TEST_REDIS_TLS_URL'];
  final tlsCa = Platform.environment['STEM_TEST_REDIS_TLS_CA_CERT'];

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

  if (tlsUrl == null || tlsUrl.isEmpty || tlsCa == null || tlsCa.isEmpty) {
    test(
      'heartbeat transport publishes over TLS',
      () {},
      skip: 'Set STEM_TEST_REDIS_TLS_URL and STEM_TEST_REDIS_TLS_CA_CERT.',
    );
  } else if (!File(tlsCa).existsSync()) {
    test(
      'heartbeat transport publishes over TLS',
      () {},
      skip: 'CA certificate not found at $tlsCa.',
    );
  } else {
    final resolvedTlsUrl = tlsUrl!;
    final resolvedTlsCa = tlsCa!;
    test('heartbeat transport publishes over TLS', () async {
      final transport = await RedisHeartbeatTransport.connect(
        resolvedTlsUrl,
        namespace: namespace,
        tls: TlsConfig(caCertificateFile: resolvedTlsCa),
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
  }
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
  } on Object {
    return false;
  }
}
