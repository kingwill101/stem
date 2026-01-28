import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

void main() {
  _runRedisTlsSuite(
    label: 'tls',
    url: Platform.environment['STEM_TEST_REDIS_TLS_URL'],
    caCertPath: Platform.environment['STEM_TEST_REDIS_TLS_CA_CERT'],
  );
  _runRedisTlsSuite(
    label: 'mtls',
    url: Platform.environment['STEM_TEST_REDIS_MTLS_URL'],
    caCertPath: Platform.environment['STEM_TEST_REDIS_MTLS_CA_CERT'],
    clientCertPath: Platform.environment['STEM_TEST_REDIS_MTLS_CLIENT_CERT'],
    clientKeyPath: Platform.environment['STEM_TEST_REDIS_MTLS_CLIENT_KEY'],
  );
}

void _runRedisTlsSuite({
  required String label,
  required String? url,
  required String? caCertPath,
  String? clientCertPath,
  String? clientKeyPath,
}) {
  final trimmedUrl = url?.trim();
  final trimmedCa = caCertPath?.trim();
  if (trimmedUrl == null || trimmedUrl.isEmpty) {
    test(
      'redis $label integration skipped',
      () {},
      skip: 'Set STEM_TEST_REDIS_${label.toUpperCase()}_URL to run TLS tests.',
    );
    return;
  }
  if (trimmedCa == null || trimmedCa.isEmpty) {
    test(
      'redis $label integration skipped',
      () {},
      skip: 'Set STEM_TEST_REDIS_${label.toUpperCase()}_CA_CERT.',
    );
    return;
  }
  if (!File(trimmedCa).existsSync()) {
    test(
      'redis $label integration skipped',
      () {},
      skip: 'CA certificate not found at $trimmedCa.',
    );
    return;
  }
  if (label == 'mtls') {
    final trimmedClientCert = clientCertPath?.trim();
    final trimmedClientKey = clientKeyPath?.trim();
    if (trimmedClientCert == null || trimmedClientCert.isEmpty) {
      test(
        'redis $label integration skipped',
        () {},
        skip: 'Set STEM_TEST_REDIS_MTLS_CLIENT_CERT.',
      );
      return;
    }
    if (trimmedClientKey == null || trimmedClientKey.isEmpty) {
      test(
        'redis $label integration skipped',
        () {},
        skip: 'Set STEM_TEST_REDIS_MTLS_CLIENT_KEY.',
      );
      return;
    }
    if (!File(trimmedClientCert).existsSync()) {
      test(
        'redis $label integration skipped',
        () {},
        skip: 'Client certificate not found at $trimmedClientCert.',
      );
      return;
    }
    if (!File(trimmedClientKey).existsSync()) {
      test(
        'redis $label integration skipped',
        () {},
        skip: 'Client key not found at $trimmedClientKey.',
      );
      return;
    }
    clientCertPath = trimmedClientCert;
    clientKeyPath = trimmedClientKey;
  }

  final resolvedUrl = trimmedUrl!;
  final resolvedCa = trimmedCa!;
  final resolvedClientCert = clientCertPath;
  final resolvedClientKey = clientKeyPath;
  final tls = TlsConfig(
    caCertificateFile: resolvedCa,
    clientCertificateFile: resolvedClientCert,
    clientKeyFile: resolvedClientKey,
  );

  group('redis $label tls integration', () {
    final namespace =
        'stem-tls-$label-${DateTime.now().microsecondsSinceEpoch}';
    final queue = 'tls-$label-queue-${DateTime.now().microsecondsSinceEpoch}';

    late RedisStreamsBroker broker;
    late RedisResultBackend backend;
    late RedisScheduleStore scheduleStore;
    late RedisLockStore lockStore;
    late RedisRevokeStore revokeStore;
    late RedisWorkflowStore workflowStore;

    setUpAll(() async {
      broker = await RedisStreamsBroker.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
      backend = await RedisResultBackend.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
      scheduleStore = await RedisScheduleStore.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
      lockStore = await RedisLockStore.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
      revokeStore = await RedisRevokeStore.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
      workflowStore = await RedisWorkflowStore.connect(
        resolvedUrl,
        namespace: namespace,
        tls: tls,
      );
    });

    tearDownAll(() async {
      await workflowStore.close();
      await revokeStore.close();
      await lockStore.close();
      await backend.close();
      await scheduleStore.remove('$namespace-schedule');
      await scheduleStore.close();
      await broker.close();
    });

    test('broker publishes and consumes over TLS', () async {
      final envelope = Envelope(
        name: 'tls.task',
        args: const {},
        queue: queue,
      );
      await broker.publish(envelope);

      final delivery = await broker
          .consume(
            RoutingSubscription.singleQueue(queue),
            consumerName: 'tls-consumer',
          )
          .first
          .timeout(const Duration(seconds: 5));

      expect(delivery.envelope.name, equals('tls.task'));
      await broker.ack(delivery);
      await broker.purge(queue);
    });

    test('result backend writes and reads over TLS', () async {
      const taskId = 'tls-result';
      await backend.set(taskId, TaskState.running, meta: const {'tls': true});
      final status = await backend.get(taskId);
      expect(status, isNotNull);
      expect(status!.state, TaskState.running);
      expect(status.meta['tls'], isTrue);
    });

    test('schedule store processes entries over TLS', () async {
      final entry = ScheduleEntry(
        id: '$namespace-schedule',
        taskName: 'tls.schedule',
        queue: queue,
        spec: IntervalScheduleSpec(every: const Duration(milliseconds: 50)),
      );
      await scheduleStore.upsert(entry);
      final due = await scheduleStore.due(
        DateTime.now().add(const Duration(milliseconds: 60)),
      );
      expect(due, isNotEmpty);
    });

    test('lock store acquires and releases over TLS', () async {
      final lock = await lockStore.acquire(
        '$namespace-lock',
        ttl: const Duration(milliseconds: 200),
      );
      expect(lock, isNotNull);
      await lock!.release();
    });

    test('revoke store upserts over TLS', () async {
      final entry = RevokeEntry(
        namespace: namespace,
        taskId: 'tls-revoke',
        version: generateRevokeVersion(),
        issuedAt: DateTime.now().toUtc(),
      );
      await revokeStore.upsertAll([entry]);
      final entries = await revokeStore.list(namespace);
      expect(entries.any((item) => item.taskId == 'tls-revoke'), isTrue);
    });

    test('workflow store creates runs over TLS', () async {
      final runId = await workflowStore.createRun(
        workflow: 'tls.workflow',
        params: const {'tls': true},
      );
      final state = await workflowStore.get(runId);
      expect(state, isNotNull);
      expect(state!.workflow, equals('tls.workflow'));
    });
  });
}
