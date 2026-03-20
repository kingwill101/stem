import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set when using the Postgres example.',
    );
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'report.generate',
      entrypoint: _noopEntrypoint,
      options: TaskOptions(queue: config.defaultQueue),
    ),
  ];

  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => PostgresBroker.connect(
        config.brokerUrl,
        applicationName: 'stem-postgres-enqueuer',
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

  final regions = ['us-east', 'eu-west', 'ap-south'];
  for (final region in regions) {
    final taskId = await client.enqueue(
      'report.generate',
      args: {'region': region},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued report job $taskId for $region');
  }

  await client.close();
}

FutureOr<Object?> _noopEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';
