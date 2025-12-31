import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('worker heartbeat serializes and parses correctly', () {
    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      namespace: 'stem-prod',
      timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5),
      isolateCount: 4,
      inflight: 2,
      lastLeaseRenewal: DateTime.utc(2024, 1, 2, 3, 4),
      queues: [QueueHeartbeat(name: 'default', inflight: 2)],
      extras: const {'host': 'app-01'},
    );

    final encoded = heartbeat.encode();
    final decoded = WorkerHeartbeat.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );

    expect(decoded.workerId, equals('worker-1'));
    expect(decoded.namespace, equals('stem-prod'));
    expect(decoded.isolateCount, equals(4));
    expect(decoded.inflight, equals(2));
    expect(decoded.queues, hasLength(1));
    expect(decoded.queues.first.name, equals('default'));
    expect(decoded.queues.first.inflight, equals(2));
    expect(decoded.extras['host'], equals('app-01'));
  });
}
