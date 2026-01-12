import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
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
