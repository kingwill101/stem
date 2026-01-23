import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('ScheduleSpec.fromPersisted', () {
    test('rejects null and unknown kind', () {
      expect(() => ScheduleSpec.fromPersisted(null), throwsFormatException);
      expect(
        () => ScheduleSpec.fromPersisted({'kind': 'unknown'}),
        throwsFormatException,
      );
    });

    test('parses legacy interval and cron strings', () {
      final interval = ScheduleSpec.fromPersisted('every:5s');
      expect(interval, isA<IntervalScheduleSpec>());
      expect(
        (interval as IntervalScheduleSpec).every,
        equals(const Duration(seconds: 5)),
      );

      final cron = ScheduleSpec.fromPersisted('0 12 * * *');
      expect(cron, isA<CronScheduleSpec>());
    });

    test('parses map-based specs', () {
      final interval = ScheduleSpec.fromPersisted({
        'kind': ScheduleSpecKind.interval,
        'everyMs': 1500,
        'startAt': '2025-01-01T00:00:00Z',
      });
      expect(interval, isA<IntervalScheduleSpec>());
      expect(
        (interval as IntervalScheduleSpec).every,
        equals(const Duration(milliseconds: 1500)),
      );

      final solar = ScheduleSpec.fromPersisted({
        'kind': ScheduleSpecKind.solar,
        'event': 'sunrise',
        'latitude': 42.0,
        'longitude': -71.0,
        'offset': '15m',
      });
      expect(solar, isA<SolarScheduleSpec>());

      final clocked = ScheduleSpec.fromPersisted({
        'kind': ScheduleSpecKind.clocked,
        'runAt': '2025-01-01T02:03:04Z',
        'runOnce': false,
      });
      expect(clocked, isA<ClockedScheduleSpec>());
      expect((clocked as ClockedScheduleSpec).runOnce, isFalse);

      final calendar = ScheduleSpec.fromPersisted({
        'kind': ScheduleSpecKind.calendar,
        'months': [1, '2', 3],
        'weekdays': [1, 2],
        'hours': [0],
      });
      expect(calendar, isA<CalendarScheduleSpec>());
      expect((calendar as CalendarScheduleSpec).months, equals([1, 2, 3]));
    });

    test('throws on invalid dates and durations', () {
      expect(
        () => ScheduleSpec.fromPersisted({
          'kind': ScheduleSpecKind.interval,
          'everyMs': 'bogus',
        }),
        throwsFormatException,
      );

      expect(
        () => ScheduleSpec.fromPersisted({
          'kind': ScheduleSpecKind.interval,
          'everyMs': 5000,
          'startAt': '',
        }),
        throwsFormatException,
      );
    });
  });

  group('ScheduleSpec instances', () {
    test('interval, solar, clocked, and calendar copy/serialize', () {
      final interval = IntervalScheduleSpec(
        every: const Duration(seconds: 30),
      ).copyWith(endAt: DateTime.parse('2025-01-01T01:00:00Z'));
      expect(interval.toJson()['everyMs'], 30000);
      expect(interval.endAt, isNotNull);

      final solar = SolarScheduleSpec(
        event: 'sunrise',
        latitude: 10,
        longitude: 20,
        offset: const Duration(minutes: 5),
      ).copyWith(offset: null);
      expect(solar.toJson(), containsPair('event', 'sunrise'));

      final clocked = ClockedScheduleSpec(
        runAt: DateTime.parse('2025-01-01T02:03:04Z'),
        runOnce: false,
      ).copyWith(runOnce: true);
      expect(clocked.toJson(), containsPair('runOnce', true));

      final calendar = CalendarScheduleSpec(
        months: const [1, 2],
        hours: const [9],
      ).copyWith(weekdays: const [1]);
      expect(calendar.toJson(), containsPair('weekdays', [1]));
    });

    test('calendar and clocked parsing validates inputs', () {
      final clocked = ClockedScheduleSpec.fromJson({
        'runAt': '2025-01-01T02:03:04Z',
        'runOnce': false,
      });
      expect(clocked.runOnce, isFalse);

      expect(
        () => ClockedScheduleSpec.fromJson({'runAt': null}),
        throwsFormatException,
      );

      expect(
        () => CalendarScheduleSpec.fromJson({'months': 'not-a-list'}),
        throwsFormatException,
      );
    });
  });

  group('ScheduleTimezoneResolver', () {
    test('uses fallback when name is null/empty', () {
      final resolver = ScheduleTimezoneResolver(
        (name) => tz.Location(name, const [], const [], const []),
      );
      final location = resolver.resolve('');
      expect(location.name, equals('UTC'));
    });

    test('throws when provider missing', () {
      final resolver = ScheduleTimezoneResolver(null);
      expect(() => resolver.resolve('UTC'), throwsStateError);
    });
  });
}
