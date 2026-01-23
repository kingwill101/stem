// Canvas group example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region canvas-group
Future<void> main() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<int>(
        name: 'square',
        entrypoint: (context, args) async {
          final value = args['value'] as int;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return value * value;
        },
      ),
    ],
    workerConfig: const StemWorkerConfig(
      consumerName: 'group-worker',
      concurrency: 2,
      prefetchMultiplier: 1,
    ),
  );
  await app.start();

  final canvas = app.canvas;
  const groupHandle = 'squares-demo';
  await canvas.group([
    task('square', args: <String, Object?>{'value': 2}),
    task('square', args: <String, Object?>{'value': 3}),
    task('square', args: <String, Object?>{'value': 4}),
  ], groupId: groupHandle);

  await _waitFor(() async {
    final status = await app.backend.getGroup(groupHandle);
    return status?.results.length == 3;
  });

  final groupStatus = await app.backend.getGroup(groupHandle);
  final values = groupStatus?.results.values.map((s) => s.payload).toList();
  print('Group results: $values');

  await app.close();
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
  throw TimeoutException('Timed out waiting for group completion', timeout);
}

// #endregion canvas-group
