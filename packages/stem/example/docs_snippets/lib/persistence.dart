// Persistence examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

final registry = SimpleTaskRegistry()
  ..register(
    FunctionTaskHandler<void>(
      name: 'demo',
      entrypoint: (context, args) async {
        print('Handled demo task');
        return null;
      },
    ),
  );

// #region persistence-backend-in-memory
Future<void> connectInMemoryBackend() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  await stem.enqueue('demo', args: {});
  await backend.dispose();
  broker.dispose();
}
// #endregion persistence-backend-in-memory

// #region persistence-backend-redis
Future<void> connectRedisBackend() async {
  final backend = await RedisResultBackend.connect('redis://localhost:6379/1');
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  await stem.enqueue('demo', args: {});
  await backend.close();
  await broker.close();
}
// #endregion persistence-backend-redis

// #region persistence-backend-postgres
Future<void> connectPostgresBackend() async {
  final backend = await PostgresResultBackend.connect(
    connectionString: 'postgres://postgres:postgres@localhost:5432/stem',
  );
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  await stem.enqueue('demo', args: {});
  await backend.close();
  await broker.close();
}
// #endregion persistence-backend-postgres

// #region persistence-backend-sqlite
Future<void> connectSqliteBackend() async {
  final broker = await SqliteBroker.open(File('stem_broker.sqlite'));
  final backend = await SqliteResultBackend.open(File('stem_backend.sqlite'));
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  await stem.enqueue('demo', args: {});
  await backend.close();
  await broker.close();
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
  await app.shutdown();
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
Future<void> configureRevokeStore() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final revokeStore = await PostgresRevokeStore.connect(
    'postgres://postgres:postgres@localhost:5432/stem',
  );
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    revokeStore: revokeStore,
  );

  await worker.shutdown();
  await revokeStore.close();
  await backend.dispose();
  broker.dispose();
}
// #endregion persistence-revoke-store

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
