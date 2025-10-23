import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backend = config.resultBackendUrl != null
      ? await RedisResultBackend.connect(
          config.resultBackendUrl!,
          tls: config.tls,
        )
      : InMemoryResultBackend();
  final signer = PayloadSigner.maybe(config.signing);

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'greeting.send',
        entrypoint: _greetingEntrypoint,
        options: const TaskOptions(
          queue: 'greetings',
          maxRetries: 5,
          softTimeLimit: Duration(seconds: 10),
          hardTimeLimit: Duration(seconds: 20),
        ),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'greetings',
    consumerName: 'microservice-worker',
    concurrency: 4,
    prefetchMultiplier: 2,
    signer: signer,
  );

  await worker.start();
  stdout.writeln('Worker listening for greetings...');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('Stopping worker...');
    await worker.shutdown();
    await broker.close();
    if (backend is RedisResultBackend) {
      await backend.close();
    }
    exit(0);
  });

  await Completer<void>().future; // Keep process alive
}

FutureOr<Object?> _greetingEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final name = (args['name'] as String?) ?? 'friend';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final message = 'Processed greeting for $name ';
  stdout.writeln('👋 $message (attempt ${context.attempt})');
  context.progress(1.0, data: {'message': message});
  return message;
}
