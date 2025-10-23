import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final broker = await PostgresBroker.connect(
    config.brokerUrl,
    applicationName: 'stem-postgres-enqueuer',
  );

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set when using the Postgres example.',
    );
  }

  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_demo',
    applicationName: 'stem-postgres-enqueuer',
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'report.generate',
        entrypoint: _noopEntrypoint,
        options: TaskOptions(queue: config.defaultQueue),
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: PayloadSigner.maybe(config.signing),
  );

  final regions = ['us-east', 'eu-west', 'ap-south'];
  for (final region in regions) {
    final taskId = await stem.enqueue(
      'report.generate',
      args: {'region': region},
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued report job $taskId for $region');
  }

  await broker.close();
  await backend.close();
}

FutureOr<Object?> _noopEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) => 'noop';
