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
      'STEM_RESULT_BACKEND_URL must be configured for the Redis/Postgres worker.',
    );
  }

  final backend = await PostgresResultBackend.connect(
    backendUrl,
    namespace: 'stem_demo',
    applicationName: 'stem-redis-postgres-worker',
    tls: config.tls,
  );

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'hybrid.process',
        entrypoint: _hybridEntrypoint,
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
    consumerName: 'redis-postgres-worker-1',
    concurrency: 2,
    prefetchMultiplier: 2,
  );

  await worker.start();
  stdout.writeln('Hybrid worker listening on queue "${config.defaultQueue}"');

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

FutureOr<Object?> _hybridEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final item = (args['item'] as String?) ?? 'unknown';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final message = 'Processed hybrid task for $item';
  stdout.writeln('🔄 $message');
  context.progress(1.0, data: {'item': item});
  return message;
}
