import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<int>(
        name: 'fetch.metric',
        entrypoint: (context, args) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return args['value'] as int;
        },
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'aggregate.metric',
        entrypoint: (context, args) async {
          final values =
              (context.meta['chordResults'] as List?)
                  ?.whereType<int>()
                  .toList() ??
              const [];
          final sum = values.fold<int>(0, (a, b) => a + b);
          print('Aggregated result: $sum');
          return null;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'chord-worker',
    concurrency: 3,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  final callbackId = await canvas.chord(
    body: [
      task('fetch.metric', args: <String, Object?>{'value': 5}),
      task('fetch.metric', args: <String, Object?>{'value': 7}),
      task('fetch.metric', args: <String, Object?>{'value': 11}),
    ],
    callback: task('aggregate.metric'),
  );

  await _waitFor(() async {
    final status = await backend.get(callbackId);
    return status?.state == TaskState.succeeded;
  });

  final callbackStatus = await backend.get(callbackId);
  print('Callback state: ${callbackStatus?.state}');

  await worker.shutdown();
  broker.dispose();
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
  throw TimeoutException('Timed out waiting for chord completion', timeout);
}
