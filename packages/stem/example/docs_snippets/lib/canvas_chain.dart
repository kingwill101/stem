// Canvas chain example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region canvas-chain
Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'fetch.user',
        entrypoint: (context, args) async => 'Ada',
      ),
    )
    ..register(
      FunctionTaskHandler<String>(
        name: 'enrich.user',
        entrypoint: (context, args) async {
          final prev = context.meta['chainPrevResult'] as String? ?? 'Friend';
          return '$prev Lovelace';
        },
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'send.email',
        entrypoint: (context, args) async {
          final fullName =
              context.meta['chainPrevResult'] as String? ?? 'Friend';
          print('Sending email to $fullName');
          return null;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'chain-worker',
    concurrency: 1,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  final chainResult = await canvas.chain([
    task('fetch.user'),
    task('enrich.user'),
    task('send.email'),
  ]);

  print(
    'Chain completed with state: ${chainResult.finalStatus?.state} '
    'value=${chainResult.value}',
  );

  await worker.shutdown();
  broker.dispose();
}
// #endregion canvas-chain
