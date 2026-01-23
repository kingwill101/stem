import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:test/test.dart';

void main() {
  test('payload getters expose task metadata', () {
    final envelope = Envelope(
      id: 'task-1',
      name: 'demo.task',
      args: const {},
      attempt: 2,
    );
    const worker = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: ['events'],
    );

    final received = TaskReceivedPayload(envelope: envelope, worker: worker);
    expect(received.taskId, equals('task-1'));
    expect(received.taskName, equals('demo.task'));

    final context = TaskContext(
      id: envelope.id,
      attempt: envelope.attempt,
      headers: const {},
      meta: const {},
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );
    final prerun = TaskPrerunPayload(
      envelope: envelope,
      worker: worker,
      context: context,
    );
    expect(prerun.taskId, equals('task-1'));
    expect(prerun.taskName, equals('demo.task'));
    expect(prerun.attempt, equals(2));

    final postrun = TaskPostrunPayload(
      envelope: envelope,
      worker: worker,
      context: context,
      result: const {'ok': true},
      state: TaskState.succeeded,
    );
    expect(postrun.taskId, equals('task-1'));
    expect(postrun.taskName, equals('demo.task'));
    expect(postrun.attempt, equals(2));

    final retry = TaskRetryPayload(
      envelope: envelope,
      worker: worker,
      reason: 'boom',
      nextRetryAt: DateTime.utc(2025),
    );
    expect(retry.taskId, equals('task-1'));
    expect(retry.taskName, equals('demo.task'));
    expect(retry.attempt, equals(2));
  });
}
