import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final redisConfig = _configFromPrefix('REDIS_');
  final postgresConfig = _configFromPrefix('POSTGRES_');

  final redisStem = await _buildRedisStem(redisConfig);
  final postgresStem = await _buildPostgresStem(postgresConfig);

  final redisItems = ['cache-warmup', 'metrics-snapshot'];
  for (final item in redisItems) {
    final id = await redisStem.enqueue(
      'redis.only',
      args: {'task': item},
      options: TaskOptions(queue: redisConfig.defaultQueue),
    );
    stdout.writeln('Enqueued Redis task $id for $item');
  }

  final postgresItems = ['billing-report', 'inventory-rollup'];
  for (final item in postgresItems) {
    final id = await postgresStem.enqueue(
      'postgres.only',
      args: {'task': item},
      options: TaskOptions(queue: postgresConfig.defaultQueue),
    );
    stdout.writeln('Enqueued Postgres task $id for $item');
  }

  await (redisStem.broker as RedisStreamsBroker).close();
  await (redisStem.backend as RedisResultBackend).close();
  await (postgresStem.broker as PostgresBroker).close();
  await (postgresStem.backend as PostgresResultBackend).close();
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

Future<Stem> _buildRedisStem(StemConfig config) async {
  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError('STEM_RESULT_BACKEND_URL must be set for Redis Stem');
  }
  final backend = await RedisResultBackend.connect(backendUrl, tls: config.tls);

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'redis.only',
        entrypoint: _noopEntrypoint,
        options: TaskOptions(queue: config.defaultQueue),
      ),
    );

  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: PayloadSigner.maybe(config.signing),
  );
}

Future<Stem> _buildPostgresStem(StemConfig config) async {
  final broker = await PostgresBroker.connect(
    config.brokerUrl,
    applicationName: 'stem-mixed-enqueuer',
    tls: config.tls,
  );
  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError('STEM_RESULT_BACKEND_URL must be set for Postgres Stem');
  }
  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_demo',
    applicationName: 'stem-mixed-enqueuer',
    tls: config.tls,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'postgres.only',
        entrypoint: _noopEntrypoint,
        options: TaskOptions(queue: config.defaultQueue),
      ),
    );

  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: PayloadSigner.maybe(config.signing),
  );
}

FutureOr<Object?> _noopEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) => 'noop';
