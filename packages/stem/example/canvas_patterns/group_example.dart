import 'package:stem/stem.dart';

Future<void> main() async {
  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<int>(
      name: 'square',
      entrypoint: (context, args) async {
        final value = args['value'] as int;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return value * value;
      },
    ),
  ];

  final app = await StemApp.inMemory(
    tasks: tasks,
    workerConfig: const StemWorkerConfig(
      consumerName: 'group-worker',
      concurrency: 2,
      prefetchMultiplier: 1,
    ),
  );
  const groupHandle = 'squares-demo';
  final dispatch = await app.canvas.group<int>([
    task<int>('square', args: <String, Object?>{'value': 2}),
    task<int>('square', args: <String, Object?>{'value': 3}),
    task<int>('square', args: <String, Object?>{'value': 4}),
  ], groupId: groupHandle);

  final squares = await dispatch.results
      .map((result) => result.value)
      .where((value) => value != null)
      .cast<int>()
      .toList();
  final status = await app.getGroupStatus(groupHandle);
  print('Group results: $squares (backend count: ${status?.results.length})');
  await dispatch.dispose();

  await app.shutdown();
}
