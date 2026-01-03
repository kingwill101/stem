import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<int>(
        name: 'square',
        entrypoint: (context, args) async {
          final value = args['value'] as int;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return value * value;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'group-worker',
    concurrency: 2,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  const groupHandle = 'squares-demo';
  await backend.initGroup(GroupDescriptor(id: groupHandle, expected: 3));
  final dispatch = await canvas.group<int>([
    task<int>('square', args: <String, Object?>{'value': 2}),
    task<int>('square', args: <String, Object?>{'value': 3}),
    task<int>('square', args: <String, Object?>{'value': 4}),
  ], groupId: groupHandle);

  final squares = await dispatch.results
      .map((result) => result.value)
      .where((value) => value != null)
      .cast<int>()
      .toList();
  final status = await backend.getGroup(groupHandle);
  print('Group results: $squares (backend count: ${status?.results.length})');
  await dispatch.dispose();

  await worker.shutdown();
  await backend.dispose();
  broker.dispose();
}
