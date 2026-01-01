// Canvas chord example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region canvas-chord
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
          final values = (context.meta['chordResults'] as List?)
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
  final chordResult = await canvas.chord(
    body: [
      task('fetch.metric', args: <String, Object?>{'value': 5}),
      task('fetch.metric', args: <String, Object?>{'value': 7}),
      task('fetch.metric', args: <String, Object?>{'value': 11}),
    ],
    callback: task('aggregate.metric'),
  );

  print('Callback task id: ${chordResult.callbackTaskId}');
  print('Chord values: ${chordResult.values}');

  await worker.shutdown();
  broker.dispose();
}
// #endregion canvas-chord
