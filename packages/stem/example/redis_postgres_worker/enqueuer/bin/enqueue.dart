import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set when using the Redis/Postgres example.',
    );
  }

  final backend = await PostgresResultBackend.connect(
    connectionString: backendUrl,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'hybrid.process',
        entrypoint: _noop,
        options: TaskOptions(queue: config.defaultQueue),
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: PayloadSigner.maybe(config.signing),
  );

  final items = ['alpha', 'beta', 'gamma'];
  for (final item in items) {
    final taskId = await stem.enqueue(
      'hybrid.process',
      args: {'item': item},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued hybrid job $taskId for $item');
  }

  await broker.close();
  await backend.close();
}

FutureOr<Object?> _noop(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';
