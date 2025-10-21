import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/stem.dart';

void main() {
  group('InMemoryBroker', () {
    test('delivers published messages to consumers', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 50),
        defaultVisibilityTimeout: const Duration(seconds: 1),
      );

      final envelope = Envelope(name: 'task', args: const {});
      await broker.publish(envelope);

      final delivery = await broker
          .consume('default', prefetch: 1)
          .first
          .timeout(const Duration(seconds: 1));

      expect(delivery.envelope.id, equals(envelope.id));
      await broker.ack(delivery);
      broker.dispose();
    });

    test('delayed messages become available after ETA', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 50),
      );

      final envelope = Envelope(
        name: 'delayed',
        args: const {},
        notBefore: DateTime.now().add(const Duration(milliseconds: 80)),
      );
      await broker.publish(envelope);

      final stream = broker.consume('default');
      final delivery = await stream.first.timeout(const Duration(seconds: 1));
      expect(delivery.envelope.name, equals('delayed'));
      await broker.ack(delivery);
      broker.dispose();
    });

    test('expired leases are reclaimed and re-delivered', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
        defaultVisibilityTimeout: const Duration(milliseconds: 30),
      );

      final envelope = Envelope(
        name: 'timeout-task',
        args: const {},
        visibilityTimeout: const Duration(milliseconds: 30),
      );
      await broker.publish(envelope);

      final first =
          await broker.consume('default', consumerName: 'c-test').first;
      expect(first.envelope.id, equals(envelope.id));

      // Do not ack; wait for reclaim.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final second = await broker
          .consume('default', consumerName: 'c-test')
          .first
          .timeout(const Duration(seconds: 1));
      expect(second.envelope.id, equals(envelope.id));
      await broker.ack(second);
      broker.dispose();
    });
  });

  group('InMemoryResultBackend', () {
    test('stores and expires task statuses', () async {
      final backend = InMemoryResultBackend(
        defaultTtl: const Duration(milliseconds: 50),
      );

      await backend.set(
        'task-1',
        TaskState.succeeded,
        payload: {'value': 1},
        meta: const {'queue': 'default'},
      );

      final status = await backend.get('task-1');
      expect(status, isNotNull);
      expect(status!.payload, equals({'value': 1}));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final expired = await backend.get('task-1');
      expect(expired, isNull);
    });

    test('aggregates group results', () async {
      final backend = InMemoryResultBackend();

      await backend.initGroup(GroupDescriptor(id: 'g1', expected: 2));

      await backend.addGroupResult(
        'g1',
        TaskStatus(id: 't1', state: TaskState.succeeded, attempt: 0),
      );

      final status = await backend.addGroupResult(
        'g1',
        TaskStatus(id: 't2', state: TaskState.succeeded, attempt: 0),
      );

      expect(status, isNotNull);
      expect(status!.isComplete, isTrue);
      expect(status.results.length, equals(2));
    });
  });

  group('Integration', () {
    test('publish -> consume -> ack success', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 30),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue('noop');
      final delivery = await broker.consume('default').first;

      await backend.set(taskId, TaskState.succeeded, attempt: 0);
      await broker.ack(delivery);

      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.succeeded));

      broker.dispose();
    });

    test('failed task moves to dead letter', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 30),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_NoopTask());
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue('noop');
      final delivery = await broker.consume('default').first;

      await backend.set(
        taskId,
        TaskState.failed,
        error: const TaskError(
          type: 'Failure',
          message: 'boom',
          retryable: false,
        ),
        attempt: 1,
      );
      await broker.deadLetter(delivery, reason: 'test');

      final deadPage = await broker.listDeadLetters('default');
      expect(deadPage.entries, hasLength(1));
      expect(deadPage.entries.single.reason, equals('test'));

      broker.dispose();
    });
  });
}

class _NoopTask implements TaskHandler<void> {
  @override
  String get name => 'noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
