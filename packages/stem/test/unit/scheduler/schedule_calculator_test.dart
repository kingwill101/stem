import 'dart:math';

import 'package:property_testing/property_testing.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/scheduler/schedule_calculator.dart';
import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:test/test.dart';

import '../../support/property_test_helpers.dart';

void main() {
  test('ScheduleCalculator computes next interval and applies jitter', () {
    final calculator = ScheduleCalculator(random: Random(0));
    final spec = IntervalScheduleSpec(every: const Duration(seconds: 10));
    final entry = ScheduleEntry(
      id: 'interval',
      taskName: 'task',
      queue: 'default',
      spec: spec,
      lastRunAt: DateTime.utc(2025),
      jitter: const Duration(seconds: 1),
    );

    final now = DateTime.utc(2025, 1, 1, 0, 0, 5);
    final nextRun = calculator.nextRun(entry, now);

    expect(nextRun.isAfter(DateTime.utc(2025, 1, 1, 0, 0, 9)), isTrue);
    expect(nextRun.isBefore(DateTime.utc(2025, 1, 1, 0, 0, 12)), isTrue);
  });

  test('ScheduleCalculator handles clocked schedules', () {
    final calculator = ScheduleCalculator();
    final runAt = DateTime.utc(2025);

    final once = ScheduleEntry(
      id: 'clocked-once',
      taskName: 'task',
      queue: 'default',
      spec: ClockedScheduleSpec(runAt: runAt),
    );

    final recurring = ScheduleEntry(
      id: 'clocked-repeat',
      taskName: 'task',
      queue: 'default',
      spec: ClockedScheduleSpec(runAt: runAt, runOnce: false),
    );

    final now = DateTime.utc(2025, 1, 1, 0, 0, 5);
    expect(calculator.nextRun(once, now), runAt);

    final nextRecurring = calculator.nextRun(recurring, now);
    expect(nextRecurring.isAfter(runAt), isTrue);
  });

  test('ScheduleCalculator throws when interval exceeds endAt', () {
    final calculator = ScheduleCalculator();
    final spec = IntervalScheduleSpec(
      every: const Duration(seconds: 10),
      endAt: DateTime.utc(2025, 1, 1, 0, 0, 5),
    );
    final entry = ScheduleEntry(
      id: 'interval-end',
      taskName: 'task',
      queue: 'default',
      spec: spec,
      lastRunAt: DateTime.utc(2025),
    );

    expect(
      () => calculator.nextRun(entry, DateTime.utc(2025, 1, 1, 0, 0, 6)),
      throwsStateError,
    );
  });

  test('ScheduleCalculator computes cron schedules', () {
    final calculator = ScheduleCalculator();
    final entry = ScheduleEntry(
      id: 'cron',
      taskName: 'task',
      queue: 'default',
      spec: CronScheduleSpec(expression: '*/5 * * * *'),
      lastRunAt: DateTime.utc(2025),
    );

    final next = calculator.nextRun(entry, DateTime.utc(2025));
    expect(next.minute, 5);
  });

  test('ScheduleCalculator rejects invalid cron expressions', () {
    final calculator = ScheduleCalculator();
    final entry = ScheduleEntry(
      id: 'cron-bad',
      taskName: 'task',
      queue: 'default',
      spec: CronScheduleSpec(expression: 'bad'),
    );

    expect(
      () => calculator.nextRun(entry, DateTime.utc(2025)),
      throwsFormatException,
    );
  });

  test('ScheduleCalculator computes calendar schedules', () {
    final calculator = ScheduleCalculator();
    final entry = ScheduleEntry(
      id: 'calendar',
      taskName: 'task',
      queue: 'default',
      spec: CalendarScheduleSpec(minutes: const [0], hours: const [0]),
      lastRunAt: DateTime.utc(2025),
    );

    final next = calculator.nextRun(entry, DateTime.utc(2025));
    expect(next, DateTime.utc(2025, 1, 2));
  });

  test('interval schedules are monotonic after now', () async {
    final gen = Gen.integer(min: 1, max: 60 * 1000).flatMap((everyMs) {
      return Gen.integer(min: 0, max: everyMs * 5).map(
        (offsetMs) => _IntervalCase(everyMs, offsetMs),
      );
    });

    final runner = PropertyTestRunner<_IntervalCase>(
      gen,
      (sample) async {
        final spec = IntervalScheduleSpec(
          every: Duration(milliseconds: sample.everyMs),
        );
        final now = DateTime.utc(2025, 1, 1, 12);
        final lastRunAt = now.subtract(
          Duration(milliseconds: sample.offsetMs),
        );
        final entry = ScheduleEntry(
          id: 'schedule-${sample.everyMs}-${sample.offsetMs}',
          taskName: 'demo.task',
          queue: 'default',
          spec: spec,
          lastRunAt: lastRunAt,
        );

        final calculator = ScheduleCalculator();
        final nextRun = calculator.nextRun(
          entry,
          now,
          includeJitter: false,
        );

        expect(nextRun.isBefore(now), isFalse);
      },
      fastPropertyConfig,
    );

    await expectProperty(
      runner,
      description: 'interval monotonicity',
    );
  });
}

class _IntervalCase {
  _IntervalCase(this.everyMs, this.offsetMs);

  final int everyMs;
  final int offsetMs;
}
