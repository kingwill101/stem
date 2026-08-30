import 'package:stem/portable.dart';
import 'package:test/test.dart';

void main() {
  group('TaskProcessor', () {
    test('executes a handler with a platform attempt override', () async {
      final processor = _processor([
        _definition('portable.success').handler(
          entrypoint: (context, args) async => {
            'value': args['value'],
            'attempt': context.attempt,
          },
          executionMode: TaskExecutionMode.inline,
        ),
      ]);
      final envelope = Envelope(
        id: 'stable-id',
        name: 'portable.success',
        args: const {'value': 42},
      );

      final outcome = await processor.process(envelope, deliveryAttempt: 2);

      expect(outcome, isA<TaskProcessSuccess>());
      final success = outcome as TaskProcessSuccess;
      expect(success.taskId, 'stable-id');
      expect(success.attempt, 2);
      expect(success.value, {'value': 42, 'attempt': 2});
    });

    test('returns an explicit retry without transport side effects', () async {
      final processor = _processor([
        _definition('portable.retry').handler(
          entrypoint: (context, args) async {
            await context.retry(
              countdown: const Duration(seconds: 3),
              maxRetries: 4,
            );
            return null;
          },
          executionMode: TaskExecutionMode.inline,
        ),
      ]);
      final envelope = Envelope(
        id: 'retry-id',
        name: 'portable.retry',
        args: const {},
        attempt: 1,
        maxRetries: 4,
      );

      final outcome = await processor.process(envelope);

      expect(outcome, isA<TaskProcessRetry>());
      final retry = outcome as TaskProcessRetry;
      expect(retry.explicit, isTrue);
      expect(retry.delay, const Duration(seconds: 3));
      expect(retry.nextAttempt, 2);
      expect(retry.nextEnvelope.id, 'retry-id');
    });

    test('classifies exhausted failures as terminal', () async {
      final processor = _processor([
        _definition('portable.failure').handler(
          entrypoint: (context, args) async => throw StateError('failed'),
          executionMode: TaskExecutionMode.inline,
        ),
      ]);
      final envelope = Envelope(
        name: 'portable.failure',
        args: const {},
        attempt: 2,
        maxRetries: 2,
      );

      final outcome = await processor.process(envelope);

      expect(outcome, isA<TaskProcessFailure>());
      expect((outcome as TaskProcessFailure).retryExhausted, isTrue);
    });

    test('rejects unregistered tasks', () async {
      final outcome = await _processor(const []).process(
        Envelope(name: 'missing', args: const {}),
      );

      expect(outcome, isA<TaskProcessRejected>());
      expect(
        (outcome as TaskProcessRejected).reason,
        TaskRejectionReason.unregisteredTask,
      );
    });

    test('skips a delivery with an existing terminal result', () async {
      final envelope = Envelope(
        id: 'duplicate-id',
        name: 'portable.success',
        args: const {},
      );
      final status = TaskStatus(
        id: envelope.id,
        state: TaskState.succeeded,
        attempt: 0,
      );

      final outcome = await _processor(const []).process(
        envelope,
        existingStatus: status,
      );

      expect(outcome, isA<TaskProcessSkipped>());
      expect((outcome as TaskProcessSkipped).existingStatus, same(status));
    });

    test('cancels an expired envelope before handler execution', () async {
      var executed = false;
      final processor = _processor([
        _definition('portable.expired').handler(
          entrypoint: (context, args) async {
            executed = true;
            return null;
          },
          executionMode: TaskExecutionMode.inline,
        ),
      ]);
      final envelope = Envelope(
        name: 'portable.expired',
        args: const {},
        meta: {
          'stem.expiresAt': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      );

      final outcome = await processor.process(envelope);

      expect(outcome, isA<TaskProcessCancelled>());
      expect(
        (outcome as TaskProcessCancelled).reason,
        TaskCancellationReason.expired,
      );
      expect(executed, isFalse);
    });
  });
}

TaskDefinition<Map<String, Object?>, Object?> _definition(String name) {
  return TaskDefinition<Map<String, Object?>, Object?>(
    name: name,
    encodeArgs: (args) => args,
    decodeArgs: (args) => args,
  );
}

TaskProcessor _processor(Iterable<TaskHandler<Object?>> tasks) {
  final registry = InMemoryTaskRegistry();
  for (final task in tasks) {
    registry.register(task);
  }
  return TaskProcessor(registry: registry, randomSeed: 1);
}
