// Canvas chord example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region canvas-chord
Future<void> main() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<int>(
        name: 'fetch.metric',
        entrypoint: (context, args) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return args['value'] as int;
        },
      ),
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
    ],
    workerConfig: const StemWorkerConfig(
      consumerName: 'chord-worker',
      concurrency: 3,
      prefetchMultiplier: 1,
    ),
  );
  await app.start();

  final canvas = app.canvas;
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

  await app.close();
}

// #endregion canvas-chord
