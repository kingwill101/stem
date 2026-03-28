import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'fetch.user',
      entrypoint: (context, args) async => 'Ada',
    ),
    FunctionTaskHandler<String>(
      name: 'enrich.user',
      entrypoint: (context, args) async {
        final prev = context.meta.valueOr<String>('chainPrevResult', 'Friend');
        return '$prev Lovelace';
      },
    ),
    FunctionTaskHandler<Object?>(
      name: 'send.email',
      entrypoint: (context, args) async {
        final fullName = context.meta.valueOr<String>(
          'chainPrevResult',
          'Friend',
        );
        print('Sending email to $fullName');
        return null;
      },
    ),
  ];

  final app = await StemApp.inMemory(
    tasks: tasks,
    workerConfig: const StemWorkerConfig(
      consumerName: 'chain-worker',
      concurrency: 1,
      prefetchMultiplier: 1,
    ),
  );
  final chainResult = await app.canvas.chain<Object?>([
    task('fetch.user'),
    task('enrich.user'),
    task('send.email'),
  ]);

  await _waitFor(() async {
    final status = await app.getTaskStatus(chainResult.finalTaskId);
    return status?.state == TaskState.succeeded;
  });

  final status = await app.getTaskStatus(chainResult.finalTaskId);
  print('Chain completed with state: ${status?.state}');

  await app.shutdown();
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
