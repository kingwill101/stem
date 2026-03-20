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
      'STEM_RESULT_BACKEND_URL must be set when using the Redis/Postgres example.',
    );
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'hybrid.process',
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

  final items = ['alpha', 'beta', 'gamma'];
  for (final item in items) {
    final taskId = await client.enqueue(
      'hybrid.process',
      args: {'item': item},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued hybrid job $taskId for $item');
  }

  await client.close();
}

FutureOr<Object?> _noop(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';
