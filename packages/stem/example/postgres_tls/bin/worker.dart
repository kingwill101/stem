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
    connectionString: backendUrl,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'reports.generate',
        entrypoint: _reportEntrypoint,
        options: TaskOptions(
          queue: config.defaultQueue,
          maxRetries: 3,
          visibilityTimeout: const Duration(seconds: 30),
        ),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: config.defaultQueue,
    consumerName: 'postgres-tls-worker',
    concurrency: 2,
    observability: ObservabilityConfig(
      heartbeatInterval: const Duration(seconds: 5),
      namespace: 'tls-demo',
    ),
    signer: PayloadSigner.maybe(config.signing),
  );

  await worker.start();
  stdout.writeln('Postgres TLS worker consuming "${config.defaultQueue}"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping Postgres TLS worker ($signal)...');
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
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final message =
      'Generated TLS report for $region (attempt ${context.attempt})';
  stdout.writeln('[tls] $message');
  context.progress(1.0, data: {'region': region});
  return message;
}
