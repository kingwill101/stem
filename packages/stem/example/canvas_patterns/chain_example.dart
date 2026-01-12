import 'dart:async';

import 'package:stem/stem.dart';

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
  final chainResult = await canvas.chain<Object?>([
    task('fetch.user'),
    task('enrich.user'),
    task('send.email'),
  ]);

  await _waitFor(() async {
    final status = await backend.get(chainResult.finalTaskId);
    return status?.state == TaskState.succeeded;
  });

  final status = await backend.get(chainResult.finalTaskId);
  print('Chain completed with state: ${status?.state}');

  await worker.shutdown();
  await backend.close();
  await broker.close();
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException('Timed out waiting for chain completion', timeout);
}
