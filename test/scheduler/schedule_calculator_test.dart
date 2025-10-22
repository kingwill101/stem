import 'dart:math';

import 'package:test/test.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/scheduler/schedule_calculator.dart';
import 'package:stem/src/scheduler/schedule_spec.dart';

void main() {
  group('ScheduleCalculator', () {
    final now = DateTime.utc(2025, 1, 1, 12, 0);

    ScheduleEntry buildEntry({
      ScheduleSpec? spec,
      String? specExpression,
      DateTime? lastRun,
      Duration? jitter,
    }) {
      return ScheduleEntry(
        id: 'sample',
        taskName: 'sample.task',
        queue: 'default',
        spec: spec ?? ScheduleSpec.fromPersisted(specExpression ?? 'every:5s'),
        lastRunAt: lastRun,
        jitter: jitter,
      );
    }

    test('computes next run for every: expressions without jitter', () {
      final calculator = ScheduleCalculator(random: Random(1));
      final entry = buildEntry(specExpression: 'every:30s');

      final result = calculator.nextRun(entry, now, includeJitter: false);

      expect(result.difference(now), equals(const Duration(seconds: 30)));
    });

    test('applies jitter when provided', () {
      final referenceRandom = Random(42);
      final calculator = ScheduleCalculator(random: Random(42));
      final entry = buildEntry(
        specExpression: 'every:1s',
        jitter: const Duration(milliseconds: 500),
      );

      final expectedJitterMs = referenceRandom.nextInt(
        entry.jitter!.inMilliseconds + 1,
      );
      final result = calculator.nextRun(entry, now);
      final elapsed = result.difference(now);
      final expectedElapsed =
          const Duration(seconds: 1) + Duration(milliseconds: expectedJitterMs);

      expect(elapsed, equals(expectedElapsed));
    });

    test('supports millisecond every expressions', () {
      final calculator = ScheduleCalculator();
      final entry = buildEntry(specExpression: 'every:250ms');

      final result = calculator.nextRun(entry, now, includeJitter: false);

      expect(result.difference(now), equals(const Duration(milliseconds: 250)));
    });

    test('throws for invalid every expression', () {
      expect(
        () => buildEntry(specExpression: 'every:'),
        throwsFormatException,
      );
    });

    test('throws for unsupported every unit', () {
      expect(
        () => buildEntry(specExpression: 'every:10q'),
        throwsFormatException,
      );
    });

    test('computes cron expression for next minute when satisfied', () {
      final calculator = ScheduleCalculator();
      final entry = buildEntry(
        specExpression: '*/15 9-17 * * 1-5',
        lastRun: now,
      );

      final result = calculator.nextRun(entry, now);

      expect(result.isAfter(now), isTrue);
      expect(result.minute % 15, equals(0));
      expect(result.hour, inInclusiveRange(9, 17));
      expect(
        result.weekday,
        inInclusiveRange(DateTime.monday, DateTime.friday),
      );
    });

    test('respects cron weekday aliases for Sunday', () {
      final calculator = ScheduleCalculator();
      final sunday = DateTime.utc(2025, 1, 5, 8, 45); // Sunday
      final entry = buildEntry(
        specExpression: '0 9 * * 0',
        lastRun: sunday,
      );

      final nextRun = calculator.nextRun(entry, sunday);

      expect(nextRun.weekday, equals(DateTime.sunday));
      expect(nextRun.hour, equals(9));
      expect(nextRun.minute, equals(0));
    });

    test('throws when cron expression has invalid field count', () {
      final calculator = ScheduleCalculator();
      final entry = buildEntry(specExpression: '*/5 0 * *');

      expect(() => calculator.nextRun(entry, now), throwsFormatException);
    });

    test('throws when cron range start exceeds end', () {
      final calculator = ScheduleCalculator();
      final entry = buildEntry(specExpression: '0 0 10-5 * *');

      expect(() => calculator.nextRun(entry, now), throwsFormatException);
    });

    test('throws when cron value outside valid bounds', () {
      final calculator = ScheduleCalculator();
      final entry = buildEntry(specExpression: '0 0 0 * *');

      expect(() => calculator.nextRun(entry, now), throwsA(isA<RangeError>()));
    });
  });
}
