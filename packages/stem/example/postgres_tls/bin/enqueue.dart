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
      'STEM_RESULT_BACKEND_URL must be set for the Postgres TLS example.',
    );
  }

  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_tls_demo',
    applicationName: 'stem-postgres-tls-enqueuer',
    tls: config.tls,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'reports.generate',
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

  final regions = ['emea', 'amer', 'apac'];
  for (final region in regions) {
    final id = await stem.enqueue(
      'reports.generate',
      args: {'region': region},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued TLS demo task $id for $region');
  }

  await broker.close();
  await backend.close();
}

FutureOr<Object?> _noop(
  TaskInvocationContext context,
  Map<String, Object?> args,
) => 'noop';
