import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set for the Postgres TLS example.',
    );
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'reports.generate',
      entrypoint: _noop,
      options: TaskOptions(queue: config.defaultQueue),
    ),
  ];

  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => RedisStreamsBroker.connect(
        config.brokerUrl,
        tls: config.tls,
      ),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => PostgresResultBackend.connect(
        connectionString: backendUrl,
      ),
      dispose: (backend) => backend.close(),
    ),
    tasks: tasks,
    signer: PayloadSigner.maybe(config.signing),
  );

  final regions = ['emea', 'amer', 'apac'];
  for (final region in regions) {
    final id = await client.enqueue(
      'reports.generate',
      args: {'region': region},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued TLS demo task $id for $region');
  }

  await client.close();
}

FutureOr<Object?> _noop(
  TaskInvocationContext context,
  Map<String, Object?> args,
) => 'noop';
