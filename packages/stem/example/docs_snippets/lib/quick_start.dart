// Quick start examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region quickstart-main
// #region quickstart-tasks
// #region quickstart-task-resize
class ResizeImageTask extends TaskHandler<void> {
  @override
  String get name => 'media.resize';

  @override
  TaskOptions get options => const TaskOptions(
    maxRetries: 5,
    softTimeLimit: Duration(seconds: 10),
    hardTimeLimit: Duration(seconds: 20),
    priority: 7,
    rateLimit: '20/m',
    visibilityTimeout: Duration(seconds: 60),
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final file = args['file'] as String? ?? 'unknown.png';
    context.heartbeat();
    print('[media.resize] resizing $file (attempt ${context.attempt})');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
// #endregion quickstart-task-resize

// #region quickstart-task-email
class EmailReceiptTask extends TaskHandler<void> {
  @override
  String get name => 'billing.email-receipt';

  @override
  TaskOptions get options => const TaskOptions(
    queue: 'emails',
    maxRetries: 3,
    priority: 9,
  );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'customer@example.com';
    print('[billing.email-receipt] sent to $to');
  }
}
// #endregion quickstart-task-email
// #endregion quickstart-tasks

Future<void> main() async {
  // #region quickstart-bootstrap
  // In-memory adapters make the quick start self-contained.
  final app = await StemApp.inMemory(
    tasks: [ResizeImageTask(), EmailReceiptTask()],
    workerConfig: const StemWorkerConfig(
      queue: 'default',
      consumerName: 'quickstart-worker',
      concurrency: 4,
    ),
  );

  unawaited(app.start());

  final stem = app.stem;
  // #endregion quickstart-bootstrap

  // #region quickstart-enqueue
  final resizeId = await stem.enqueue(
    'media.resize',
    args: {'file': 'report.png'},
  );

  final emailId = await stem.enqueue(
    'billing.email-receipt',
    args: {'to': 'alice@example.com'},
    options: const TaskOptions(priority: 10),
    notBefore: DateTime.now().add(const Duration(seconds: 5)),
    meta: {'orderId': 4242},
  );

  print('Enqueued tasks: resize=$resizeId email=$emailId');
  // #endregion quickstart-enqueue

  // #region quickstart-canvas-call
  final canvas = app.canvas;
  await runCanvasExample(canvas);
  // #endregion quickstart-canvas-call

  // #region quickstart-inspect
  await Future<void>.delayed(const Duration(seconds: 6));
  final resizeStatus = await app.backend.get(resizeId);
  print('Resize status: ${resizeStatus?.state} (${resizeStatus?.attempt})');

  await app.shutdown();
  // #endregion quickstart-inspect
}
// #endregion quickstart-main

// #region quickstart-canvas-example
Future<void> runCanvasExample(Canvas canvas) async {
  final chainResult = await canvas.chain([
    task(
      'media.resize',
      args: {'file': 'canvas.png'},
      options: const TaskOptions(priority: 5),
    ),
    task(
      'billing.email-receipt',
      args: {'to': 'ops@example.com'},
      options: const TaskOptions(queue: 'emails'),
    ),
  ]);

  print('Canvas chain complete. Final task id = ${chainResult.finalTaskId}');
}

// #endregion quickstart-canvas-example
