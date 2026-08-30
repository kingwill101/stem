import 'dart:async';
import 'dart:convert';

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

    test('rejects a negative platform delivery attempt', () async {
      await expectLater(
        _processor(const []).process(
          Envelope(name: 'portable.invalid-attempt', args: const {}),
          deliveryAttempt: -1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects envelopes that fail signature verification', () async {
      final secret = base64.encode(utf8.encode('portable-secret'));
      final signer = PayloadSigner(
        SigningConfig.fromEnvironment({
          'STEM_SIGNING_KEYS': 'primary:$secret',
          'STEM_SIGNING_ACTIVE_KEY': 'primary',
        }),
      );
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()
          ..register(
            _definition('portable.signed').handler(
              entrypoint: (context, args) async => null,
              executionMode: TaskExecutionMode.inline,
            ),
          ),
        signer: signer,
      );

      final outcome = await processor.process(
        Envelope(name: 'portable.signed', args: const {}),
      );

      expect(outcome, isA<TaskProcessRejected>());
      expect(
        (outcome as TaskProcessRejected).reason,
        TaskRejectionReason.invalidSignature,
      );
      expect(outcome.error, isA<SignatureVerificationException>());
    });

    test('rejects payloads that do not decode to a map', () async {
      final handler = _definition('portable.invalid-payload').handler(
        entrypoint: (context, args) async => null,
        executionMode: TaskExecutionMode.inline,
      );
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()..register(handler),
        additionalEncoders: const [_ListPayloadEncoder()],
      );

      final outcome = await processor.process(
        Envelope(
          name: handler.name,
          args: const {},
          headers: const {stemArgsEncoderHeader: 'test-list'},
        ),
      );

      expect(outcome, isA<TaskProcessRejected>());
      expect(
        (outcome as TaskProcessRejected).reason,
        TaskRejectionReason.invalidPayload,
      );
    });

    test('honors cooperative cancellation before execution', () async {
      var executed = false;
      final token = TaskCancellationToken()..cancel();
      final processor = _processor([
        _definition('portable.cancelled').handler(
          entrypoint: (context, args) async {
            executed = true;
            return null;
          },
          executionMode: TaskExecutionMode.inline,
        ),
      ]);

      final outcome = await processor.process(
        Envelope(name: 'portable.cancelled', args: const {}),
        control: TaskExecutionControl(cancellation: token),
      );

      expect(outcome, isA<TaskProcessCancelled>());
      expect(
        (outcome as TaskProcessCancelled).reason,
        TaskCancellationReason.cancelled,
      );
      expect(executed, isFalse);
    });

    test('runs middleware and reports handler errors', () async {
      final middleware = _RecordingMiddleware();
      final handler = _definition('portable.middleware').handler(
        entrypoint: (context, args) async => throw StateError('failed'),
        executionMode: TaskExecutionMode.inline,
      );
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()..register(handler),
        middleware: [middleware],
      );

      final outcome = await processor.process(
        Envelope(name: handler.name, args: const {}),
      );

      expect(outcome, isA<TaskProcessFailure>());
      expect(middleware.executions, 1);
      expect(middleware.errors, 1);
    });

    test('classifies hard timeouts as terminal failures', () async {
      final handler =
          _definition(
            'portable.timeout',
            options: const TaskOptions(
              hardTimeLimit: Duration(milliseconds: 1),
            ),
          ).handler(
            entrypoint: (context, args) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return null;
            },
            executionMode: TaskExecutionMode.inline,
          );

      final outcome = await _processor([handler]).process(
        Envelope(name: handler.name, args: const {}),
      );

      expect(outcome, isA<TaskProcessFailure>());
      expect((outcome as TaskProcessFailure).error, isA<TimeoutException>());
    });

    test('applies automatic retry policy and backoff', () async {
      final handler =
          _definition(
            'portable.auto-retry',
            options: const TaskOptions(
              maxRetries: 3,
              retryPolicy: TaskRetryPolicy(
                backoff: true,
                jitter: false,
                defaultDelay: Duration(seconds: 2),
                maxRetries: 3,
                autoRetryFor: ['StateError'],
              ),
            ),
          ).handler(
            entrypoint: (context, args) async => throw StateError('retry'),
            executionMode: TaskExecutionMode.inline,
          );

      final outcome = await _processor([handler]).process(
        Envelope(name: handler.name, args: const {}, attempt: 1),
      );

      expect(outcome, isA<TaskProcessRetry>());
      final retry = outcome as TaskProcessRetry;
      expect(retry.explicit, isFalse);
      expect(retry.nextAttempt, 2);
      expect(retry.delay, const Duration(seconds: 4));
    });
  });
}

TaskDefinition<Map<String, Object?>, Object?> _definition(
  String name, {
  TaskOptions options = const TaskOptions(),
}) {
  return TaskDefinition<Map<String, Object?>, Object?>(
    name: name,
    encodeArgs: (args) => args,
    decodeArgs: (args) => args,
    defaultOptions: options,
  );
}

TaskProcessor _processor(Iterable<TaskHandler<Object?>> tasks) {
  final registry = InMemoryTaskRegistry();
  tasks.forEach(registry.register);
  return TaskProcessor(registry: registry, randomSeed: 1);
}

class _ListPayloadEncoder extends TaskPayloadEncoder {
  const _ListPayloadEncoder();

  @override
  String get id => 'test-list';

  @override
  Object? decode(Object? stored) => const [1, 2, 3];

  @override
  Object? encode(Object? value) => value;
}

class _RecordingMiddleware implements Middleware {
  int executions = 0;
  int errors = 0;

  @override
  Future<void> onConsume(Delivery delivery, Future<void> Function() next) =>
      next();

  @override
  Future<void> onEnqueue(Envelope envelope, Future<void> Function() next) =>
      next();

  @override
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  ) async {
    errors += 1;
  }

  @override
  Future<void> onExecute(
    TaskContext context,
    Future<void> Function() next,
  ) async {
    executions += 1;
    await next();
  }
}
