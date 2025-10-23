import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set for the Redis worker.',
    );
  }

  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backend = await RedisResultBackend.connect(backendUrl, tls: config.tls);

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'redis.only',
        entrypoint: _redisEntrypoint,
        options: TaskOptions(
          queue: config.defaultQueue,
          maxRetries: 5,
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
    consumerName: 'redis-worker-1',
    concurrency: 2,
  );

  await worker.start();
  stdout.writeln('Redis worker consuming from "${config.defaultQueue}"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping Redis worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

FutureOr<Object?> _redisEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final task = (args['task'] as String?) ?? 'unknown';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final message = 'Redis worker processed $task';
  stdout.writeln('🔁 $message');
  context.progress(1.0, data: {'task': task});
  return message;
}
