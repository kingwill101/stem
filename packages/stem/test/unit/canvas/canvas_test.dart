import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/stem.dart';

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

    test('group executes all tasks', () async {
      final ids = await canvas.group([
        task('echo', args: {'value': 1}),
        task('echo', args: {'value': 2}),
      ]);

      final statuses = await Future.wait(
        ids.map((id) => _waitForSuccess(backend, id)),
      );
      expect(statuses.map((s) => s.payload), containsAll([1, 2]));
    });

    test('chain sequences tasks', () async {
      final finalId = await canvas.chain([
        task('echo', args: {'value': 1}),
        task('sum', args: {'add': 2}),
      ]);

      final status = await _waitForSuccess(backend, finalId);
      expect(status.payload, equals(3));
    });

    test('chord triggers callback after group completes', () async {
      final callbackId = await canvas.chord(
        body: [
          task('echo', args: {'value': 2}),
          task('echo', args: {'value': 3}),
        ],
        callback: task('sum'),
      );

      final status = await _waitForSuccess(backend, callbackId);
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
    var total = 0;
    if (previous is num) {
      total += previous.toInt();
    }
    total += (args['add'] as num?)?.toInt() ?? 0;
    return total;
  }
}
