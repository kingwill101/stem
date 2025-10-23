import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set for the Postgres worker.',
    );
  }

  final broker = await PostgresBroker.connect(
    config.brokerUrl,
    applicationName: 'stem-mixed-postgres-worker',
  );
  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_demo',
    applicationName: 'stem-mixed-postgres-worker',
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'postgres.only',
        entrypoint: _postgresEntrypoint,
        options: TaskOptions(
          queue: config.defaultQueue,
          maxRetries: 3,
          softTimeLimit: const Duration(seconds: 5),
          hardTimeLimit: const Duration(seconds: 12),
        ),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: config.defaultQueue,
    consumerName: 'postgres-worker-1',
    concurrency: 2,
  );

  await worker.start();
  stdout.writeln('Postgres worker consuming from "${config.defaultQueue}"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping Postgres worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

FutureOr<Object?> _postgresEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final task = (args['task'] as String?) ?? 'unknown';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final message = 'Postgres worker processed $task';
  stdout.writeln('📄 $message');
  context.progress(1.0, data: {'task': task});
  return message;
}
