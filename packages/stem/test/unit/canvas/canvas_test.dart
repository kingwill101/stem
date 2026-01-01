import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Canvas', () {
    late InMemoryBroker broker;
    late InMemoryResultBackend backend;
    late SimpleTaskRegistry registry;
    late Worker worker;
    late Canvas canvas;

    setUp(() async {
      broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      backend = InMemoryResultBackend();
      registry = SimpleTaskRegistry()
        ..register(_EchoTask())
        ..register(_SumTask());
      canvas = Canvas(broker: broker, backend: backend, registry: registry);
      worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'canvas-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
      );
      await worker.start();
    });

    tearDown(() async {
      await worker.shutdown();
      broker.dispose();
    });

    test('group executes all tasks and streams typed results', () async {
      final dispatch = await canvas.group<int>([
        task<int>('echo', args: {'value': 4}),
        task<int>('echo', args: {'value': 6}),
      ]);

      final received = await dispatch.results
          .map((result) => result.value)
          .toList();
      final typed = received.whereType<int>().toList();
      expect(typed, containsAll([4, 6]));

      final statuses = await Future.wait(
        dispatch.taskIds.map((id) => _waitForSuccess(backend, id)),
      );
      expect(statuses.map((s) => s.payload), containsAll([4, 6]));
      await dispatch.dispose();
    });

    test('chain returns typed payload', () async {
      final result = await canvas.chain<int>([
        task<int>('echo', args: {'value': 1}),
        task<int>('sum', args: {'add': 2}),
      ]);

      expect(result.value, 3);
      expect(result.finalStatus?.state, TaskState.succeeded);
    });

    test('chord returns typed body results', () async {
      final result = await canvas.chord<int>(
        body: [
          task<int>('echo', args: {'value': 2}),
          task<int>('echo', args: {'value': 3}),
        ],
        callback: task('sum'),
      );

      expect(result.values, containsAll(<int>[2, 3]));
      final status = await _waitForSuccess(backend, result.callbackTaskId);
      expect(status.payload, equals(5));
    });
  });
}

Future<TaskStatus> _waitForSuccess(
  ResultBackend backend,
  String taskId, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final start = DateTime.now();
  while (true) {
    final status = await backend.get(taskId);
    if (status != null && status.state == TaskState.succeeded) {
      return status;
    }
    if (DateTime.now().difference(start) > timeout) {
      throw TimeoutException('Task $taskId did not succeed in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

class _EchoTask implements TaskHandler<int> {
  @override
  String get name => 'echo';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<int> call(TaskContext context, Map<String, Object?> args) async {
    return args['value'] as int? ?? 0;
  }
}

class _SumTask implements TaskHandler<int> {
  @override
  String get name => 'sum';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<int> call(TaskContext context, Map<String, Object?> args) async {
    final chordResults = context.meta['chordResults'];
    if (chordResults is List) {
      return chordResults.whereType<num>().fold<int>(
        0,
        (acc, value) => acc + value.toInt(),
      );
    }
    final previous = context.meta['chainPrevResult'];
    final previousValue = previous is num ? previous.toInt() : 0;
    final addValue = (args['add'] as num?)?.toInt() ?? 0;
    return previousValue + addValue;
  }
}
