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

    test(
      'submitBatch returns stable id and terminal lifecycle summary',
      () async {
        final batch = await canvas.submitBatch<int>([
          task<int>('echo', args: {'value': 8}),
          task<int>('echo', args: {'value': 13}),
        ]);

        expect(batch.batchId, isNotEmpty);
        expect(batch.taskIds, hasLength(2));

        final status = await _waitForBatchTerminal(canvas, batch.batchId);
        expect(status.state, BatchLifecycleState.succeeded);
        expect(status.expected, equals(2));
        expect(status.completed, equals(2));
        expect(status.succeededCount, equals(2));
        expect(status.failedCount, equals(0));
        expect(status.cancelledCount, equals(0));
        expect(status.failedTaskIds, isEmpty);
        expect(status.meta['stem.batch'], isTrue);
      },
    );

    test('submitBatch with an existing batchId is idempotent', () async {
      const batchId = 'batch-fixed';
      final first = await canvas.submitBatch<int>([
        task<int>('echo', args: {'value': 1}),
        task<int>('echo', args: {'value': 2}),
      ], batchId: batchId);
      final second = await canvas.submitBatch<int>([
        task<int>('echo', args: {'value': 99}),
      ], batchId: batchId);

      expect(second.batchId, equals(first.batchId));
      expect(second.taskIds, equals(first.taskIds));

      final status = await _waitForBatchTerminal(canvas, batchId);
      expect(status.expected, equals(2));
      expect(status.meta['stem.batch.taskCount'], equals(2));
    });

    test(
      'inspectBatch counts only terminal group entries as completed',
      () async {
        const batchId = 'batch-non-terminal';
        await backend.initGroup(
          GroupDescriptor(
            id: batchId,
            expected: 2,
            meta: const {'stem.batch': true},
          ),
        );
        await backend.addGroupResult(
          batchId,
          TaskStatus(id: 'task-queued', state: TaskState.queued, attempt: 0),
        );
        await backend.addGroupResult(
          batchId,
          TaskStatus(
            id: 'task-succeeded',
            state: TaskState.succeeded,
            attempt: 0,
          ),
        );

        final status = await canvas.inspectBatch(batchId);
        expect(status, isNotNull);
        expect(status!.completed, equals(1));
        expect(status.succeededCount, equals(1));
        expect(status.state, equals(BatchLifecycleState.running));
      },
    );
  });
}

Future<TaskStatus> _waitForSuccess(
  ResultBackend backend,
  String taskId, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  return _waitForNonNull<TaskStatus>(
    () async {
      final status = await backend.get(taskId);
      if (status?.state == TaskState.succeeded) {
        return status;
      }
      return null;
    },
    timeout: timeout,
    errorMessage: 'Task $taskId did not succeed in time',
  );
}

Future<BatchStatus> _waitForBatchTerminal(
  Canvas canvas,
  String batchId, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  return _waitForNonNull<BatchStatus>(
    () async {
      final status = await canvas.inspectBatch(batchId);
      if (status != null && status.isTerminal) {
        return status;
      }
      return null;
    },
    timeout: timeout,
    errorMessage: 'Batch $batchId did not complete in time',
  );
}

Future<T> _waitForNonNull<T>(
  Future<T?> Function() read, {
  required Duration timeout,
  required String errorMessage,
}) async {
  final start = DateTime.now();
  while (true) {
    final value = await read();
    if (value != null) {
      return value;
    }
    if (DateTime.now().difference(start) > timeout) {
      throw TimeoutException(errorMessage);
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
