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

  test('worker heartbeat exposes typed extras helpers', () {
    final heartbeat = WorkerHeartbeat(
      workerId: 'worker-1',
      timestamp: DateTime.utc(2025),
      isolateCount: 3,
      inflight: 2,
      queues: [QueueHeartbeat(name: 'default', inflight: 2)],
      extras: const {
        PayloadCodec.versionKey: 2,
        'env': 'test',
        'region': 'us-east-1',
      },
    );

    expect(heartbeat.extraValue<String>('env'), 'test');
    expect(
      heartbeat.extraValueOr<String>('missing', 'fallback'),
      'fallback',
    );
    expect(heartbeat.requiredExtraValue<String>('region'), 'us-east-1');
    expect(
      heartbeat.extrasJson<_HeartbeatExtras>(
        decode: _HeartbeatExtras.fromJson,
      ),
      isA<_HeartbeatExtras>()
          .having((value) => value.env, 'env', 'test')
          .having((value) => value.region, 'region', 'us-east-1'),
    );
    expect(
      heartbeat.extrasVersionedJson<_HeartbeatExtras>(
        version: 2,
        decode: _HeartbeatExtras.fromVersionedJson,
      ),
      isA<_HeartbeatExtras>()
          .having((value) => value.env, 'env', 'test')
          .having((value) => value.region, 'region', 'us-east-1'),
    );
  });
}

class _HeartbeatExtras {
  const _HeartbeatExtras({required this.env, required this.region});

  factory _HeartbeatExtras.fromJson(Map<String, dynamic> json) {
    return _HeartbeatExtras(
      env: json['env'] as String,
      region: json['region'] as String,
    );
  }

  factory _HeartbeatExtras.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _HeartbeatExtras.fromJson(json);
  }

  final String env;
  final String region;
}
