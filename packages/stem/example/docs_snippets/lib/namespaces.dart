// Namespace configuration snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region namespaces-broker
Future<RedisStreamsBroker> connectNamespacedBroker() {
  return RedisStreamsBroker.connect(
    'redis://localhost:6379/0',
    namespace: 'prod-us-east',
  );
}
// #endregion namespaces-broker

// #region namespaces-backend
Future<RedisResultBackend> connectNamespacedBackend() {
  return RedisResultBackend.connect(
    'redis://localhost:6379/1',
    namespace: 'prod-us-east',
  );
}
// #endregion namespaces-backend

// #region namespaces-broker-backend
Future<void> configureNamespace() async {
  final broker = await RedisStreamsBroker.connect(
    'redis://localhost:6379/0',
    namespace: 'prod-us-east',
  );
  final backend = await RedisResultBackend.connect(
    'redis://localhost:6379/1',
    namespace: 'prod-us-east',
  );

  await broker.close();
  await backend.close();
}
// #endregion namespaces-broker-backend

// #region namespaces-isolation
Future<void> isolateNamespaces() async {
  final teamABroker = await RedisStreamsBroker.connect(
    'redis://localhost:6379/0',
    namespace: 'team-a',
  );
  final teamBBroker = await RedisStreamsBroker.connect(
    'redis://localhost:6379/0',
    namespace: 'team-b',
  );

  await teamABroker.close();
  await teamBBroker.close();
}
// #endregion namespaces-isolation

// #region namespaces-worker
Future<void> configureWorkerNamespace() async {
  final registry = SimpleTaskRegistry();
  final broker = InMemoryBroker(namespace: 'prod-us-east');
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    heartbeatNamespace: 'prod-us-east',
  );

  await worker.shutdown();
  await backend.close();
  await broker.close();
}

// #endregion namespaces-worker
