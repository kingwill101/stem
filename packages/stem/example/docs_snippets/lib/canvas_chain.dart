// Canvas chain example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region canvas-chain
Future<void> main() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<String>(
        name: 'fetch.user',
        entrypoint: (context, args) async => 'Ada',
      ),
      FunctionTaskHandler<String>(
        name: 'enrich.user',
        entrypoint: (context, args) async {
          final prev = context.meta['chainPrevResult'] as String? ?? 'Friend';
          return '$prev Lovelace';
        },
      ),
      FunctionTaskHandler<Object?>(
        name: 'send.email',
        entrypoint: (context, args) async {
          final fullName =
              context.meta['chainPrevResult'] as String? ?? 'Friend';
          print('Sending email to $fullName');
          return null;
        },
      ),
    ],
    workerConfig: const StemWorkerConfig(
      consumerName: 'chain-worker',
      concurrency: 1,
      prefetchMultiplier: 1,
    ),
  );
  await app.start();

  final canvas = app.canvas;
  final chainResult = await canvas.chain([
    task('fetch.user'),
    task('enrich.user'),
    task('send.email'),
  ]);

  print(
    'Chain completed with state: ${chainResult.finalStatus?.state} '
    'value=${chainResult.value}',
  );

  await app.close();
}

// #endregion canvas-chain
