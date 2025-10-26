import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final broker = await PostgresBroker.connect(
    config.brokerUrl,
    applicationName: 'stem-postgres-worker',
    tls: config.tls,
  );

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be configured for the Postgres worker.',
    );
  }

  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_demo',
    applicationName: 'stem-postgres-worker',
    tls: config.tls,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'report.generate',
        entrypoint: _reportEntrypoint,
        options: TaskOptions(
          queue: config.defaultQueue,
          maxRetries: 3,
          softTimeLimit: const Duration(seconds: 5),
          hardTimeLimit: const Duration(seconds: 10),
        ),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: config.defaultQueue,
    consumerName: 'postgres-worker-1',
    concurrency: 3,
    prefetchMultiplier: 2,
    observability: ObservabilityConfig(
      namespace: 'postgres-demo',
      heartbeatInterval: const Duration(seconds: 5),
    ),
  );

  await worker.start();
  stdout.writeln('Postgres worker listening on queue "${config.defaultQueue}"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

FutureOr<Object?> _reportEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final region = (args['region'] as String?) ?? 'unknown';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 750));
  final message =
      'Generated analytics report for $region (attempt ${context.attempt})';
  stdout.writeln('📊 $message');
  context.progress(1.0, data: {'region': region});
  return message;
}
