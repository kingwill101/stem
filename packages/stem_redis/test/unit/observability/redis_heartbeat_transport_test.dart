import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

import '../../support/fakes/fake_redis.dart';

void main() {
  test('connect delegates to commandFactory with TLS metadata', () async {
    final connection = FakeRedisConnection();
    final command = FakeRedisCommand(connection);

    Uri? capturedUri;
    TlsConfig? capturedTls;

    final transport = await RedisHeartbeatTransport.connect(
      'rediss://example.com:6380/1',
      namespace: 'ops',
      tls: const TlsConfig(allowInsecure: true),
      commandFactory: (uri, tls) async {
        capturedUri = uri;
        capturedTls = tls;
        return (connection: connection, command: command);
      },
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.scheme, equals('rediss'));
    expect(capturedUri!.host, equals('example.com'));
    expect(capturedUri!.port, equals(6380));
    expect(capturedUri!.pathSegments, contains('1'));
    expect(capturedTls, isNotNull);
    expect(capturedTls!.allowInsecure, isTrue);

    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-a',
      namespace: 'ops',
      timestamp: DateTime.utc(2024),
      isolateCount: 1,
      inflight: 0,
      queues: const [],
    );

    await transport.publish(heartbeat);

    expect(
      command.sent,
      contains(
        equals(['PUBLISH', WorkerHeartbeat.topic('ops'), heartbeat.encode()]),
      ),
    );

    await transport.close();
    expect(connection.closed, isTrue);
  });
}
