// Namespace configuration snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

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
  broker.dispose();
}
// #endregion namespaces-worker
