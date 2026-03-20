// Persistence examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

final demoTasks = [
  FunctionTaskHandler<void>(
    name: 'demo',
    entrypoint: (context, args) async {
      print('Handled demo task');
      return null;
    },
  ),
];

// #region persistence-backend-in-memory
Future<void> connectInMemoryBackend() async {
  final client = await StemClient.create(
    broker: StemBrokerFactory.inMemory(),
    backend: StemBackendFactory.inMemory(),
    tasks: demoTasks,
  );
  await client.enqueue('demo', args: {});
  await client.close();
}
// #endregion persistence-backend-in-memory

// #region persistence-backend-redis
Future<void> connectRedisBackend() async {
  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => RedisStreamsBroker.connect('redis://localhost:6379'),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => RedisResultBackend.connect('redis://localhost:6379/1'),
      dispose: (backend) => backend.close(),
    ),
    tasks: demoTasks,
  );
  await client.enqueue('demo', args: {});
  await client.close();
}
// #endregion persistence-backend-redis

// #region persistence-backend-postgres
Future<void> connectPostgresBackend() async {
  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => RedisStreamsBroker.connect('redis://localhost:6379'),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => PostgresResultBackend.connect(
        connectionString: 'postgres://postgres:postgres@localhost:5432/stem',
      ),
      dispose: (backend) => backend.close(),
    ),
    tasks: demoTasks,
  );
  await client.enqueue('demo', args: {});
  await client.close();
}
// #endregion persistence-backend-postgres

// #region persistence-backend-sqlite
Future<void> connectSqliteBackend() async {
  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => SqliteBroker.open(File('stem_broker.sqlite')),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => SqliteResultBackend.open(File('stem_backend.sqlite')),
      dispose: (backend) => backend.close(),
    ),
    tasks: demoTasks,
  );
  await client.enqueue('demo', args: {});
  await client.close();
}
// #endregion persistence-backend-sqlite

// #region persistence-encoders
class Base64PayloadEncoder extends TaskPayloadEncoder {
  const Base64PayloadEncoder();
  @override
  Object? encode(Object? value) =>
      value is String ? base64Encode(utf8.encode(value)) : value;
  @override
  Object? decode(Object? stored) =>
      stored is String ? utf8.decode(base64Decode(stored)) : stored;
}

Future<void> configureEncoders() async {
  final app = await StemApp.inMemory(
    tasks: const [],
    argsEncoder: const JsonTaskPayloadEncoder(),
    resultEncoder: const Base64PayloadEncoder(),
    additionalEncoders: const [GzipPayloadEncoder()],
  );
  await app.close();
}
// #endregion persistence-encoders

// #region persistence-beat-stores
Future<void> configureBeatStores() async {
  final scheduleStore = await RedisScheduleStore.connect(
    'redis://localhost:6379/2',
  );
  final lockStore = await RedisLockStore.connect('redis://localhost:6379/3');
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');

  final beat = Beat(
    broker: broker,
    store: scheduleStore,
    lockStore: lockStore,
  );

  await beat.stop();
  await broker.close();
  await scheduleStore.close();
  await lockStore.close();
}
// #endregion persistence-beat-stores

// #region persistence-revoke-store
Future<void> configurePostgresRevokeStore() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final revokeStore = await PostgresRevokeStore.connect(
    'postgres://postgres:postgres@localhost:5432/stem',
  );
  final worker = Worker(
    broker: broker,
    backend: backend,
    tasks: demoTasks,
    revokeStore: revokeStore,
  );

  await worker.shutdown();
  await revokeStore.close();
  await backend.close();
  await broker.close();
}
// #endregion persistence-revoke-store

// #region persistence-revoke-store-sqlite
Future<void> configureSqliteRevokeStore() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final revokeStore = await SqliteRevokeStore.open(
    File('stem_revoke.sqlite'),
    namespace: 'stem',
  );
  final worker = Worker(
    broker: broker,
    backend: backend,
    tasks: demoTasks,
    revokeStore: revokeStore,
  );

  await worker.shutdown();
  await revokeStore.close();
  await backend.close();
  await broker.close();
}
// #endregion persistence-revoke-store-sqlite

class GzipPayloadEncoder extends TaskPayloadEncoder {
  const GzipPayloadEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

Future<void> main() async {
  await configureEncoders();
  print('Payload encoders configured.');
}
