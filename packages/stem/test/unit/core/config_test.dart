import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemConfig.fromEnvironment', () {
    test('parses values with trimming, defaults, and dedupe', () {
      final config = StemConfig.fromEnvironment({
        'STEM_BROKER_URL': ' redis://localhost:6379 ',
        'STEM_RESULT_BACKEND_URL': ' postgres://localhost:5432/stem ',
        'STEM_SCHEDULE_STORE_URL': '  ',
        'STEM_REVOKE_STORE_URL': 'file:///tmp/revokes.json',
        'STEM_DEFAULT_QUEUE': '  high  ',
        'STEM_PREFETCH_MULTIPLIER': '4',
        'STEM_DEFAULT_MAX_RETRIES': '5',
        'STEM_ROUTING_CONFIG': ' /etc/stem/routing.yaml ',
        'STEM_WORKER_QUEUES': 'default,  ,analytics,default ',
        'STEM_WORKER_BROADCASTS': 'broadcast, broadcast ,',
        'STEM_TLS_ALLOW_INSECURE': 'true',
      });

      expect(config.brokerUrl, ' redis://localhost:6379 ');
      expect(config.resultBackendUrl, 'postgres://localhost:5432/stem');
      expect(config.scheduleStoreUrl, isNull);
      expect(config.revokeStoreUrl, 'file:///tmp/revokes.json');
      expect(config.defaultQueue, 'high');
      expect(config.prefetchMultiplier, 4);
      expect(config.defaultMaxRetries, 5);
      expect(config.routingConfigPath, '/etc/stem/routing.yaml');
      expect(config.workerQueues, ['default', 'analytics']);
      expect(config.workerBroadcasts, ['broadcast']);
      expect(config.tls.allowInsecure, isTrue);
    });

    test('falls back to defaults when values are invalid', () {
      final config = StemConfig.fromEnvironment({
        'STEM_BROKER_URL': 'redis://localhost:6379',
        'STEM_DEFAULT_QUEUE': '   ',
        'STEM_PREFETCH_MULTIPLIER': '0',
        'STEM_DEFAULT_MAX_RETRIES': '-2',
        'STEM_WORKER_QUEUES': ' ,  ',
      });

      expect(config.defaultQueue, 'default');
      expect(config.prefetchMultiplier, 2);
      expect(config.defaultMaxRetries, 3);
      expect(config.workerQueues, isEmpty);
    });
  });

  test('StemConfig.copyWith overrides values', () {
    final original = StemConfig(
      brokerUrl: 'redis://localhost:6379',
      resultBackendUrl: 'postgres://localhost:5432/stem',
      scheduleStoreUrl: 'file:///tmp/schedule.json',
      revokeStoreUrl: 'file:///tmp/revokes.json',
      routingConfigPath: '/etc/stem/routing.yaml',
      workerQueues: const ['default'],
      workerBroadcasts: const ['broadcast'],
    );

    final updated = original.copyWith(
      defaultQueue: 'high',
      prefetchMultiplier: 5,
      workerQueues: const ['priority'],
    );

    expect(updated.brokerUrl, original.brokerUrl);
    expect(updated.resultBackendUrl, original.resultBackendUrl);
    expect(updated.defaultQueue, 'high');
    expect(updated.prefetchMultiplier, 5);
    expect(updated.workerQueues, ['priority']);
    expect(updated.workerBroadcasts, original.workerBroadcasts);
  });
}
