import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final redisConfig = _configFromPrefix('REDIS_');
  final postgresConfig = _configFromPrefix('POSTGRES_');

  final redisClient = await _buildRedisClient(redisConfig);
  final postgresClient = await _buildPostgresClient(postgresConfig);

  final redisItems = ['cache-warmup', 'metrics-snapshot'];
  for (final item in redisItems) {
    final id = await redisClient.enqueue(
      'redis.only',
      args: {'task': item},
      options: TaskOptions(queue: redisConfig.defaultQueue),
    );
    stdout.writeln('Enqueued Redis task $id for $item');
  }

  final postgresItems = ['billing-report', 'inventory-rollup'];
  for (final item in postgresItems) {
    final id = await postgresClient.enqueue(
      'postgres.only',
      args: {'task': item},
      options: TaskOptions(queue: postgresConfig.defaultQueue),
    );
    stdout.writeln('Enqueued Postgres task $id for $item');
  }

  await redisClient.close();
  await postgresClient.close();
}

StemConfig _configFromPrefix(String prefix) {
  final overrides = <String, String>{};
  for (final entry in Platform.environment.entries) {
    if (entry.key.startsWith(prefix)) {
      overrides[entry.key.substring(prefix.length)] = entry.value;
    }
  }
  if (overrides.isEmpty) {
    throw StateError('Missing environment variables for prefix $prefix');
  }
  return StemConfig.fromEnvironment(overrides);
}

Future<StemClient> _buildRedisClient(StemConfig config) async {
  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError('STEM_RESULT_BACKEND_URL must be set for Redis Stem');
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'redis.only',
      entrypoint: _noopEntrypoint,
      options: TaskOptions(queue: config.defaultQueue),
    ),
  ];

  return StemClient.create(
    broker: StemBrokerFactory(
      create: () =>
          RedisStreamsBroker.connect(config.brokerUrl, tls: config.tls),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => RedisResultBackend.connect(backendUrl, tls: config.tls),
      dispose: (backend) => backend.close(),
    ),
    tasks: tasks,
    signer: PayloadSigner.maybe(config.signing),
  );
}

Future<StemClient> _buildPostgresClient(StemConfig config) async {
  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError('STEM_RESULT_BACKEND_URL must be set for Postgres Stem');
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'postgres.only',
      entrypoint: _noopEntrypoint,
      options: TaskOptions(queue: config.defaultQueue),
    ),
  ];

  return StemClient.create(
    broker: StemBrokerFactory(
      create: () => PostgresBroker.connect(
        config.brokerUrl,
        applicationName: 'stem-mixed-enqueuer',
        tls: config.tls,
      ),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => PostgresResultBackend.connect(connectionString: backendUrl),
      dispose: (backend) => backend.close(),
    ),
    tasks: tasks,
    signer: PayloadSigner.maybe(config.signing),
  );
}

FutureOr<Object?> _noopEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';
