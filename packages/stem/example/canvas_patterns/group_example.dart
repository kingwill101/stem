import 'dart:async';

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
  final dispatch = await canvas.group<int>([
    task<int>('square', args: <String, Object?>{'value': 2}),
    task<int>('square', args: <String, Object?>{'value': 3}),
    task<int>('square', args: <String, Object?>{'value': 4}),
  ], groupId: groupHandle);

  await _waitFor(() async {
    final status = await backend.getGroup(groupHandle);
    return status?.results.length == 3;
  });

  final squares = await dispatch.results
      .map((result) => result.value)
      .whereType<int>()
      .toList();
  print('Group results: $squares');
  await dispatch.dispose();

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
  throw TimeoutException('Timed out waiting for group completion', timeout);
}
