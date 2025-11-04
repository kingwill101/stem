import 'package:stem/stem.dart';

import '../brokers/redis_broker.dart';
import '../backend/redis_backend.dart';
import 'redis_workflow_store.dart';

StemBrokerFactory redisBrokerFactory(
  String uri, {
  String namespace = 'stem',
  Duration blockTime = const Duration(seconds: 5),
  int delayedDrainBatch = 128,
  Duration defaultVisibilityTimeout = const Duration(seconds: 30),
  Duration claimInterval = const Duration(seconds: 30),
  TlsConfig? tls,
}) {
  return StemBrokerFactory(
    create: () async => RedisStreamsBroker.connect(
      uri,
      namespace: namespace,
      blockTime: blockTime,
      delayedDrainBatch: delayedDrainBatch,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      claimInterval: claimInterval,
      tls: tls,
    ),
    dispose: (broker) async {
      if (broker is RedisStreamsBroker) {
        await broker.close();
      }
    },
  );
}

StemBackendFactory redisResultBackendFactory(
  String uri, {
  String namespace = 'stem',
  Duration defaultTtl = const Duration(days: 1),
  Duration groupDefaultTtl = const Duration(days: 1),
  Duration heartbeatTtl = const Duration(minutes: 1),
  TlsConfig? tls,
}) {
  return StemBackendFactory(
    create: () async => RedisResultBackend.connect(
      uri,
      namespace: namespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
      tls: tls,
    ),
    dispose: (backend) async {
      if (backend is RedisResultBackend) {
        await backend.close();
      }
    },
  );
}

WorkflowStoreFactory redisWorkflowStoreFactory(
  String uri, {
  String namespace = 'stem',
}) {
  return WorkflowStoreFactory(
    create: () async => RedisWorkflowStore.connect(uri, namespace: namespace),
    dispose: (store) async {
      if (store is RedisWorkflowStore) {
        await store.close();
      }
    },
  );
}
