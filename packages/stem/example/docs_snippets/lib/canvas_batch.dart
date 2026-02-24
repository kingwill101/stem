// Canvas batch examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';

// #region canvas-batch
Future<void> main() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<int>(
        name: 'batch.double',
        entrypoint: (context, args) async {
          final value = args['value'] as int? ?? 0;
          return value * 2;
        },
      ),
    ],
    workerConfig: const StemWorkerConfig(
      consumerName: 'batch-worker',
      concurrency: 1,
      prefetchMultiplier: 1,
    ),
  );
  await app.start();

  final submission = await app.canvas.submitBatch<int>([
    task('batch.double', args: {'value': 1}),
    task('batch.double', args: {'value': 2}),
    task('batch.double', args: {'value': 3}),
  ]);

  // Batches may still be running immediately after submission.
  BatchStatus? status;
  for (var i = 0; i < 20; i += 1) {
    status = await app.canvas.inspectBatch(submission.batchId);
    if (status?.isTerminal == true) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  print(
    'Batch ${submission.batchId} state=${status?.state} '
    'completed=${status?.completed}/${status?.expected}',
  );

  await app.close();
}

// #endregion canvas-batch
