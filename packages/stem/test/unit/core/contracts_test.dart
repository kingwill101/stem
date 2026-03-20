import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:test/test.dart';

void main() {
  group('RoutingSubscription', () {
    test('trims inputs and rejects empty', () {
      expect(
        () => RoutingSubscription(queues: const ['  '], broadcastChannels: []),
        throwsArgumentError,
      );

      final subscription = RoutingSubscription(
        queues: const [' default ', ''],
        broadcastChannels: const ['  broadcast  ', ''],
      );

      expect(subscription.queues, equals(['default']));
      expect(subscription.broadcastChannels, equals(['broadcast']));
    });

    test('singleQueue trims and validates', () {
      expect(() => RoutingSubscription.singleQueue('  '), throwsArgumentError);
      final sub = RoutingSubscription.singleQueue(' jobs ');
      expect(sub.queues, equals(['jobs']));
    });

    test('resolveQueues falls back when queues empty', () {
      final sub = RoutingSubscription(
        queues: const [],
        broadcastChannels: const ['events'],
      );
      expect(sub.resolveQueues('default'), equals(['default']));
    });
  });

  group('TaskStateX', () {
    test('isTerminal returns true only for terminal states', () {
      expect(TaskState.queued.isTerminal, isFalse);
      expect(TaskState.running.isTerminal, isFalse);
      expect(TaskState.retried.isTerminal, isFalse);
      expect(TaskState.succeeded.isTerminal, isTrue);
      expect(TaskState.failed.isTerminal, isTrue);
      expect(TaskState.cancelled.isTerminal, isTrue);
    });
  });

  group('TaskStatus/TaskError', () {
    test('round trips through json', () {
      const error = TaskError(
        type: 'Boom',
        message: 'failed',
        stack: 'stack',
        retryable: true,
        meta: {'code': 500},
      );
      final status = TaskStatus(
        id: 'task-1',
        state: TaskState.running,
        attempt: 2,
        payload: const {'ok': true},
        error: error,
        meta: const {'queue': 'default'},
      );

      final decoded = TaskStatus.fromJson(status.toJson());

      expect(decoded.id, equals('task-1'));
      expect(decoded.state, equals(TaskState.running));
      expect(decoded.attempt, equals(2));
      expect(decoded.payload, equals(const {'ok': true}));
      expect(decoded.error?.type, equals('Boom'));
      expect(decoded.meta['queue'], equals('default'));
    });

    test('unknown state falls back to queued', () {
      final decoded = TaskStatus.fromJson({
        'id': 'task-2',
        'state': 'unknown',
      });

      expect(decoded.state, equals(TaskState.queued));
    });

    test('metadata getters expose typed status context', () {
      final status = TaskStatus(
        id: 'task-3',
        state: TaskState.failed,
        attempt: 1,
        meta: const {
          'task': 'email.send',
          'queue': 'critical',
          'namespace': 'acme',
          'worker': 'worker-1',
          'startedAt': '2026-02-25T00:00:00Z',
          'failedAt': '2026-02-25T00:00:03Z',
          'revokedAt': '2026-02-25T00:00:04Z',
          'revokedReason': 'manual',
          'revokedBy': 'dashboard',
          'stem.expired': true,
          'stem.timeLimitMs': 1500,
          'stem.softTimeLimitMs': 750,
          'stem.parentTaskId': 'parent-1',
          'stem.rootTaskId': 'root-1',
          'stem.workflow.id': 'wf_def_01',
          'stem.workflow.name': 'invoice.flow',
          'stem.workflow.runId': 'run-123',
          'stem.workflow.step': 'charge',
          'stem.workflow.stepIndex': 2,
          'stem.workflow.iteration': 1,
          'stem.workflow.channel': 'execution',
          'stem.workflow.continuation': false,
          'stem.workflow.orchestrationQueue': 'workflow',
          'stem.workflow.continuationQueue': 'workflow',
          'stem.workflow.executionQueue': 'workflow-step',
          'stem.workflow.continuationReason': 'event',
          'stem.workflow.serialization.format': 'json',
          'stem.workflow.serialization.version': '1',
          'stem.workflow.stream.id': 'invoice_run-123',
        },
      );

      expect(status.taskName, equals('email.send'));
      expect(status.queueName, equals('critical'));
      expect(status.namespace, equals('acme'));
      expect(status.workerId, equals('worker-1'));
      expect(status.startedAt, equals(DateTime.utc(2026, 2, 25)));
      expect(status.failedAt, equals(DateTime.utc(2026, 2, 25, 0, 0, 3)));
      expect(status.wasRevoked, isTrue);
      expect(status.revokedReason, equals('manual'));
      expect(status.revokedBy, equals('dashboard'));
      expect(status.isExpired, isTrue);
      expect(status.hardTimeLimit, equals(const Duration(milliseconds: 1500)));
      expect(status.softTimeLimit, equals(const Duration(milliseconds: 750)));
      expect(status.parentTaskId, equals('parent-1'));
      expect(status.rootTaskId, equals('root-1'));
      expect(status.workflowId, equals('wf_def_01'));
      expect(status.workflowName, equals('invoice.flow'));
      expect(status.workflowRunId, equals('run-123'));
      expect(status.workflowStep, equals('charge'));
      expect(status.workflowStepIndex, equals(2));
      expect(status.workflowIteration, equals(1));
      expect(status.workflowChannel, equals('execution'));
      expect(status.workflowContinuation, isFalse);
      expect(status.workflowContinuationReason, equals('event'));
      expect(status.workflowOrchestrationQueue, equals('workflow'));
      expect(status.workflowContinuationQueue, equals('workflow'));
      expect(status.workflowExecutionQueue, equals('workflow-step'));
      expect(status.workflowSerializationFormat, equals('json'));
      expect(status.workflowSerializationVersion, equals('1'));
      expect(status.workflowStreamId, equals('invoice_run-123'));
    });

    test('payload helpers decode stored values', () {
      final status = TaskStatus(
        id: 'task-4',
        state: TaskState.succeeded,
        attempt: 0,
        payload: const {'id': 'receipt-1'},
      );
      final codec = PayloadCodec<Map<String, Object?>>.map(
        encode: (value) => value,
        decode: (json) => json,
        typeName: 'ReceiptMap',
      );

      expect(
        status.payloadValue<Map<String, Object?>>(),
        equals(const {'id': 'receipt-1'}),
      );
      expect(
        status.payloadValue<Map<String, Object?>>(codec: codec),
        equals(const {'id': 'receipt-1'}),
      );
      expect(
        status.payloadValueOr<Map<String, Object?>>(
          const {'id': 'fallback'},
          codec: codec,
        ),
        equals(const {'id': 'receipt-1'}),
      );
      expect(
        status.requiredPayloadValue<Map<String, Object?>>(codec: codec),
        equals(const {'id': 'receipt-1'}),
      );
      expect(
        status.payloadAs<Map<String, Object?>>(codec: codec),
        equals(const {'id': 'receipt-1'}),
      );
      expect(
        status.payloadJson<_ReceiptPayload>(
          decode: _ReceiptPayload.fromJson,
        ),
        isA<_ReceiptPayload>().having((value) => value.id, 'id', 'receipt-1'),
      );
    });

    test('requiredPayloadValue throws when payload is absent', () {
      final status = TaskStatus(
        id: 'task-5',
        state: TaskState.failed,
        attempt: 1,
      );

      expect(
        status.requiredPayloadValue<Map<String, Object?>>,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('task-5'),
          ),
        ),
      );
      expect(
        status.payloadValueOr<Map<String, Object?>>(
          const {'id': 'fallback'},
        ),
        equals(const {'id': 'fallback'}),
      );
      expect(
        status.payloadAs<Map<String, Object?>>(
          codec: PayloadCodec<Map<String, Object?>>.map(
            encode: (value) => value,
            decode: (json) => json,
            typeName: 'ReceiptMap',
          ),
        ),
        isNull,
      );
      expect(
        status.payloadJson<_ReceiptPayload>(
          decode: _ReceiptPayload.fromJson,
        ),
        isNull,
      );
    });
  });

  group('GroupStatus', () {
    test('exposes typed child-result decode helpers', () {
      final codec = PayloadCodec<Map<String, Object?>>.map(
        encode: (value) => value,
        decode: (json) => json,
        typeName: 'ReceiptMap',
      );
      final scalarStatus = GroupStatus(
        id: 'grp-1',
        expected: 2,
        results: {
          'task-1': TaskStatus(
            id: 'task-1',
            state: TaskState.succeeded,
            attempt: 0,
            payload: 7,
          ),
          'task-2': TaskStatus(
            id: 'task-2',
            state: TaskState.succeeded,
            attempt: 0,
            payload: 9,
          ),
        },
      );
      final dtoStatus = GroupStatus(
        id: 'grp-2',
        expected: 1,
        results: {
          'task-1': TaskStatus(
            id: 'task-1',
            state: TaskState.succeeded,
            attempt: 0,
            payload: const {'id': 'receipt-1'},
          ),
        },
      );

      expect(
        scalarStatus.resultValues<int>(),
        equals({
          'task-1': 7,
          'task-2': 9,
        }),
      );
      expect(
        dtoStatus.resultAs<Map<String, Object?>>(codec: codec),
        equals({
          'task-1': const {'id': 'receipt-1'},
        }),
      );
      expect(
        dtoStatus.resultJson<_GroupReceipt>(
          decode: _GroupReceipt.fromJson,
        ),
        {
          'task-1': isA<_GroupReceipt>()
              .having((value) => value.id, 'id', 'receipt-1'),
        },
      );
    });
  });

  group('DeadLetterEntry', () {
    test('round trips through json', () {
      final entry = DeadLetterEntry(
        envelope: Envelope(name: 'task', args: const {'a': 1}),
        deadAt: DateTime.utc(2025),
        reason: 'boom',
        meta: const {'trace': 'abc'},
      );

      final decoded = DeadLetterEntry.fromJson(entry.toJson());

      expect(decoded.envelope.name, equals('task'));
      expect(decoded.reason, equals('boom'));
      expect(decoded.meta['trace'], equals('abc'));
      expect(decoded.deadAt, equals(DateTime.utc(2025)));
    });
  });

  group('DeadLetterPage/ReplayResult', () {
    test('hasMore and count helpers', () {
      final entry = DeadLetterEntry(
        envelope: Envelope(name: 'task', args: const {}),
        deadAt: DateTime.utc(2025),
      );
      final page = DeadLetterPage(entries: [entry], nextOffset: 10);
      final result = DeadLetterReplayResult(entries: [entry], dryRun: true);

      expect(page.hasMore, isTrue);
      expect(result.count, equals(1));
      expect(result.dryRun, isTrue);
    });
  });

  group('TaskOptions/TaskRetryPolicy', () {
    test('fromJson parses durations and retry policy', () {
      final options = TaskOptions.fromJson({
        'queue': 'priority',
        'maxRetries': 5,
        'softTimeLimitMs': 1000,
        'hardTimeLimitMs': '2000',
        'groupRateLimit': '25/m',
        'groupRateKey': 'tenant:acme',
        'groupRateKeyHeader': 'x-tenant',
        'groupRateLimiterFailureMode': 'failClosed',
        'unique': true,
        'uniqueForMs': 5000,
        'priority': 3,
        'acksLate': false,
        'visibilityTimeoutMs': 3000,
        'retryPolicy': {
          'backoff': true,
          'backoffMaxMs': 9000,
          'jitter': false,
          'defaultDelayMs': 1500,
          'maxRetries': 2,
          'autoRetryFor': ['IOError'],
          'dontAutoRetryFor': ['StateError'],
        },
      });

      expect(options.queue, equals('priority'));
      expect(options.maxRetries, equals(5));
      expect(options.softTimeLimit, equals(const Duration(milliseconds: 1000)));
      expect(options.hardTimeLimit, equals(const Duration(milliseconds: 2000)));
      expect(options.groupRateLimit, equals('25/m'));
      expect(options.groupRateKey, equals('tenant:acme'));
      expect(options.groupRateKeyHeader, equals('x-tenant'));
      expect(
        options.groupRateLimiterFailureMode,
        equals(RateLimiterFailureMode.failClosed),
      );
      expect(options.unique, isTrue);
      expect(options.uniqueFor, equals(const Duration(milliseconds: 5000)));
      expect(options.priority, equals(3));
      expect(options.acksLate, isFalse);
      expect(
        options.visibilityTimeout,
        equals(const Duration(milliseconds: 3000)),
      );
      expect(options.retryPolicy?.backoff, isTrue);
      expect(options.retryPolicy?.autoRetryFor, equals(['IOError']));
    });

    test('toJson round trips retry policy', () {
      const policy = TaskRetryPolicy(
        backoff: true,
        backoffMax: Duration(seconds: 10),
        jitter: false,
        defaultDelay: Duration(milliseconds: 500),
        maxRetries: 4,
        autoRetryFor: ['Timeout'],
        dontAutoRetryFor: ['StateError'],
      );

      final decoded = TaskRetryPolicy.fromJson(policy.toJson());

      expect(decoded.backoff, isTrue);
      expect(decoded.backoffMax, equals(const Duration(seconds: 10)));
      expect(decoded.jitter, isFalse);
      expect(decoded.defaultDelay, equals(const Duration(milliseconds: 500)));
      expect(decoded.maxRetries, equals(4));
      expect(decoded.autoRetryFor, equals(['Timeout']));
      expect(decoded.dontAutoRetryFor, equals(['StateError']));
    });
  });

  group('ScheduleEntry', () {
    test('round trips through json and copyWith', () {
      final spec = IntervalScheduleSpec(
        every: const Duration(seconds: 30),
        startAt: DateTime.utc(2025),
      );
      final entry = ScheduleEntry(
        id: 'schedule-1',
        taskName: 'task',
        queue: 'default',
        spec: spec,
        args: const {'value': 1},
        kwargs: const {},
        jitter: const Duration(seconds: 1),
        lastRunAt: DateTime.utc(2025, 1, 2),
        nextRunAt: DateTime.utc(2025, 1, 3),
        lastJitter: const Duration(milliseconds: 500),
        lastError: 'oops',
        timezone: 'UTC',
        totalRunCount: 2,
        lastSuccessAt: DateTime.utc(2025, 1, 2, 1),
        lastErrorAt: DateTime.utc(2025, 1, 2, 2),
        drift: const Duration(milliseconds: 250),
        expireAt: DateTime.utc(2025, 1, 5),
        createdAt: DateTime.utc(2025, 1, 1, 0, 0, 1),
        updatedAt: DateTime.utc(2025, 1, 1, 0, 0, 2),
        version: 3,
        meta: const {'source': 'test'},
      );

      final decoded = ScheduleEntry.fromJson(entry.toJson());
      expect(decoded.id, equals('schedule-1'));
      expect(decoded.taskName, equals('task'));
      expect(decoded.queue, equals('default'));
      expect(decoded.spec, isA<IntervalScheduleSpec>());
      expect(decoded.totalRunCount, equals(2));

      final updated = entry.copyWith(lastError: null, enabled: false);
      expect(updated.lastError, isNull);
      expect(updated.enabled, isFalse);
    });
  });

  test('ScheduleConflictException string includes metadata', () {
    final error = ScheduleConflictException(
      'schedule-1',
      expectedVersion: 1,
      actualVersion: 2,
    );

    expect(error.toString(), contains('schedule-1'));
    expect(error.toString(), contains('expected: 1'));
    expect(error.toString(), contains('actual: 2'));
  });
}

class _GroupReceipt {
  const _GroupReceipt({required this.id});

  factory _GroupReceipt.fromJson(Map<String, dynamic> json) {
    return _GroupReceipt(id: json['id'] as String);
  }

  final String id;
}

class _ReceiptPayload {
  const _ReceiptPayload({required this.id});

  factory _ReceiptPayload.fromJson(Map<String, dynamic> json) {
    return _ReceiptPayload(id: json['id'] as String);
  }

  final String id;
}
