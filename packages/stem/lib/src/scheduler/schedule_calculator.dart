/// Runtime calculation engine for the scheduler subsystem.
///
/// This library provides the logic to compute the next occurrence of a task
/// based on its [ScheduleSpec] and [ScheduleEntry] state.
///
/// It handles complex temporal logic including:
/// - Timezone-aware cron parsing.
/// - Solar event calculation (via [SolarCalculator]).
/// - Interval drift prevention.
/// - Random jitter application.
library;

import 'dart:math';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:stem/src/scheduler/solar_calculator.dart';
import 'package:timezone/timezone.dart' as tz;

/// Computes the next run time for schedule entries.
///
/// The calculator uses the specification defined in the [ScheduleEntry]
/// and applies temporal logic to find the first candidate timestamp that
/// is strictly after the provided reference time.
class ScheduleCalculator {
  /// Creates a schedule calculator.
  ///
  /// - [random]: Used for generating jitter delays.
  /// - [timezoneResolver]: Used to map timezone names to [tz.Location].
  /// - [solarCalculator]: Used to compute astronomical events.
  ScheduleCalculator({
    Random? random,
    ScheduleTimezoneResolver? timezoneResolver,
    SolarCalculator? solarCalculator,
  }) : _random = random ?? Random(),
       _timezoneResolver = timezoneResolver,
       _solar = solarCalculator ?? const SolarCalculator();

  final Random _random;
  final ScheduleTimezoneResolver? _timezoneResolver;
  final SolarCalculator _solar;

  /// Calculates the next run time for a schedule [entry] relative to [now].
  ///
  /// ## Algorithm
  ///
  /// 1. Resolve the target `timezone` using [_timezoneResolver].
  /// 2. Determine the `base` reference time (either `lastRunAt` or `now`).
  /// 3. Dispatch to the specific calculation method based on the spec type.
  /// 4. If [includeJitter] is true, add a random delay between 0 and
  ///    `entry.jitter`.
  ///
  /// ## Parameters
  ///
  /// - [entry]: The schedule record containing spec and state.
  /// - [now]: The current wall-clock time.
  /// - [includeJitter]: Whether to apply the configured jitter.
  DateTime nextRun(
    ScheduleEntry entry,
    DateTime now, {
    bool includeJitter = true,
  }) {
    final spec = entry.spec;
    final location = _timezoneResolver?.resolve(entry.timezone);
    final base = entry.lastRunAt ?? now;
    DateTime next;

    switch (spec) {
      case final IntervalScheduleSpec interval:
        next = _nextInterval(interval, base, now);
      case final CronScheduleSpec cron:
        next = _nextCron(cron, base, location);
      case final SolarScheduleSpec solar:
        next = _nextSolar(solar, base, location);
      case final ClockedScheduleSpec clocked:
        next = _nextClocked(clocked, base, now);
      case final CalendarScheduleSpec calendar:
        next = _nextCalendar(calendar, base, location);
    }

    final jitter = entry.jitter;
    if (includeJitter && jitter != null && jitter > Duration.zero) {
      final jitterMs = _random.nextInt(jitter.inMilliseconds + 1);
      next = next.add(Duration(milliseconds: jitterMs));
    }
    return next;
  }

  /// Logic for fixed-interval schedules.
  ///
  /// Prevents backlog accumulation by "ticking" forward from the reference
  /// until the candidate is >= now.
  DateTime _nextInterval(
    IntervalScheduleSpec spec,
    DateTime reference,
    DateTime now,
  ) {
    final start = spec.startAt ?? reference;
    var candidate = reference.isBefore(start) ? start : reference;
    if (candidate.isBefore(now)) {
      final elapsed = now.difference(candidate);
      final ticks = (elapsed.inMilliseconds / spec.every.inMilliseconds).ceil();
      candidate = candidate.add(
        Duration(milliseconds: ticks * spec.every.inMilliseconds),
      );
    } else if (candidate.isAtSameMomentAs(reference)) {
      candidate = candidate.add(spec.every);
    }

    if (spec.endAt != null &&
        (candidate.isAfter(spec.endAt!) ||
            candidate.isAtSameMomentAs(spec.endAt!))) {
      throw StateError('Interval schedule has reached end_at boundary.');
    }
    return candidate;
  }

  /// Logic for one-time absolute timestamps.
  DateTime _nextClocked(
    ClockedScheduleSpec spec,
    DateTime reference,
    DateTime now,
  ) {
    final runAt = spec.runAt.isUtc ? spec.runAt : spec.runAt.toUtc();
    if (runAt.isBefore(now)) {
      if (spec.runOnce) {
        return runAt;
      }
      // If not run-once but in the past, return now + 1ms to trigger
      // immediate (but strictly forward) execution.
      return runAt.add(
        Duration(milliseconds: now.difference(runAt).inMilliseconds + 1),
      );
    }
    return runAt;
  }

  /// logic for standard 5-field cron expressions.
  ///
  /// Parses the expression and iterates forward minute-by-minute until
  /// a match is found across all fields (months, days, weekdays, hours,
  /// minutes).
  DateTime _nextCron(
    CronScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    if (location != null) {
      final localRef = tz.TZDateTime.from(reference, location);
      return _nextCronTz(spec, localRef, location).toUtc();
    }
    final expression = _cronExpression(spec);
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw FormatException(
        'Cron expression must have 5 fields (minute hour day month weekday). '
        'Got: "$expression"',
      );
    }

    final minuteField = _CronField.parse(fields[0], 0, 59);
    final hourField = _CronField.parse(fields[1], 0, 23);
    final dayField = _CronField.parse(fields[2], 1, 31);
    final monthField = _CronField.parse(fields[3], 1, 12);
    final weekdayField = _CronField.parse(fields[4], 0, 6, sundayValue: {0, 7});

    var candidate = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
      reference.hour,
      reference.minute,
    ).add(const Duration(minutes: 1));

    // Limit search to 1 year forward to prevent infinite loops on
    // unreachable crons.
    for (var i = 0; i < 525600; i++) {
      if (!_matches(monthField, candidate.month)) {
        candidate = DateTime.utc(candidate.year, candidate.month + 1);
        continue;
      }

      if (!_matches(dayField, candidate.day)) {
        candidate = DateTime.utc(
          candidate.year,
          candidate.month,
          candidate.day + 1,
        );
        continue;
      }

      final weekday = candidate.weekday % 7;
      if (!_matchesWeekday(weekdayField, weekday, dayField)) {
        candidate = DateTime.utc(
          candidate.year,
          candidate.month,
          candidate.day + 1,
        );
        continue;
      }

      if (!_matches(hourField, candidate.hour)) {
        candidate = DateTime.utc(
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour + 1,
        );
        continue;
      }

      if (!_matches(minuteField, candidate.minute)) {
        candidate = candidate.add(const Duration(minutes: 1));
        continue;
      }

      return candidate;
    }
    throw StateError(
      'Unable to compute next run for cron expression $expression',
    );
  }

  /// Timezone-aware cron calculation.
  ///
  /// Uses [tz.TZDateTime] for all intermediate candidates to ensure
  /// correct handling of DST transitions.
  tz.TZDateTime _nextCronTz(
    CronScheduleSpec spec,
    tz.TZDateTime reference,
    tz.Location location,
  ) {
    final expression = _cronExpression(spec);
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw FormatException(
        'Cron expression must have 5 fields (minute hour day month weekday). '
        'Got: "$expression"',
      );
    }

    final minuteField = _CronField.parse(fields[0], 0, 59);
    final hourField = _CronField.parse(fields[1], 0, 23);
    final dayField = _CronField.parse(fields[2], 1, 31);
    final monthField = _CronField.parse(fields[3], 1, 12);
    final weekdayField = _CronField.parse(fields[4], 0, 6, sundayValue: {0, 7});

    var candidate = tz.TZDateTime(
      location,
      reference.year,
      reference.month,
      reference.day,
      reference.hour,
      reference.minute,
    ).add(const Duration(minutes: 1));

    for (var i = 0; i < 525600; i++) {
      if (!_matches(monthField, candidate.month)) {
        candidate = tz.TZDateTime(
          location,
          candidate.year,
          candidate.month + 1,
        );
        continue;
      }

      if (!_matches(dayField, candidate.day)) {
        candidate = tz.TZDateTime(
          location,
          candidate.year,
          candidate.month,
          candidate.day + 1,
        );
        continue;
      }

      final weekday = candidate.weekday % 7;
      if (!_matchesWeekday(weekdayField, weekday, dayField)) {
        candidate = tz.TZDateTime(
          location,
          candidate.year,
          candidate.month,
          candidate.day + 1,
        );
        continue;
      }

      if (!_matches(hourField, candidate.hour)) {
        candidate = tz.TZDateTime(
          location,
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour + 1,
        );
        continue;
      }

      if (!_matches(minuteField, candidate.minute)) {
        candidate = candidate.add(const Duration(minutes: 1));
        continue;
      }

      return candidate;
    }
    throw StateError(
      'Unable to compute next run for cron expression $expression',
    );
  }

  /// Logic for calendar property matching.
  ///
  /// Internally maps the calendar properties to an equivalent cron
  /// expression and uses the cron calculation logic.
  DateTime _nextCalendar(
    CalendarScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    final cron = CronScheduleSpec(expression: _calendarToCron(spec));
    return _nextCron(cron, reference, location);
  }

  /// Logic for celestial event scheduling.
  DateTime _nextSolar(
    SolarScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    final start = reference.toUtc();
    final candidate = _solar.nextEvent(spec, start, location);
    if (spec.offset != null) {
      return candidate.add(spec.offset!);
    }
    return candidate;
  }

  /// Internal helper to check if a numeric value matches a cron field.
  bool _matches(_CronField field, int value) {
    return field.values == null || field.values!.contains(value);
  }

  /// Weekday matching logic (Standard Cron behavior).
  ///
  /// Note: If both Day-of-Month and Day-of-Week are restricted, standard
  /// cron behavior is to union them (fire if EITHER matches).
  bool _matchesWeekday(_CronField field, int weekday, _CronField dayField) {
    if (field.values == null) return true;
    if (dayField.values == null) {
      return field.values!.contains(weekday);
    }
    // Union behavior
    return field.values!.contains(weekday) ||
        dayField.values!.contains(weekday);
  }

  /// Sanitizes cron expressions by extracting only the first 5 fields.
  String _cronExpression(CronScheduleSpec spec) {
    if (spec.secondField != null && spec.secondField!.trim().isNotEmpty) {
      final pieces = spec.expression.trim().split(RegExp(r'\s+'));
      if (pieces.length >= 5) {
        final trimmed = pieces.take(5).join(' ');
        return trimmed;
      }
    }
    return spec.expression;
  }

  /// Converts a [CalendarScheduleSpec] to its equivalent Cron string.
  String _calendarToCron(CalendarScheduleSpec spec) {
    String serialize(List<int>? values) {
      if (values == null || values.isEmpty) return '*';
      return values.join(',');
    }

    final minute = serialize(spec.minutes);
    final hour = serialize(spec.hours);
    final day = serialize(spec.monthdays);
    final month = serialize(spec.months);
    final weekday = serialize(spec.weekdays);
    return '$minute $hour $day $month $weekday';
  }
}

/// Represents a set of permitted values for a single cron field.
class _CronField {
  /// Internal constructor.
  _CronField(this.values);

  /// Parses a cron field token into a set of allowed integers.
  ///
  /// Supports:
  /// - `*`: Wildcard (all values in range).
  /// - `,`: Value lists (`1,5,10`).
  /// - `-`: Ranges (`1-5`).
  /// - `/`: Step values (`*/5`, `1-10/2`).
  ///
  /// [sundayValue] can be used to treat multiple values as 0 (Sunday).
  factory _CronField.parse(
    String token,
    int min,
    int max, {
    Set<int>? sundayValue,
  }) {
    if (token == '*') {
      return _CronField(null);
    }
    final result = <int>{};
    for (final part in token.split(',')) {
      _expandPart(part.trim(), min, max, result, sundayValue: sundayValue);
    }
    return _CronField(result);
  }

  /// Allowed values for this field. Null means wildcard (`*`).
  final Set<int>? values;

  /// Recursively expands a cron field part into permitted values.
  static void _expandPart(
    String part,
    int min,
    int max,
    Set<int> target, {
    Set<int>? sundayValue,
  }) {
    if (part.isEmpty) {
      throw const FormatException('Empty cron field');
    }
    var step = 1;
    var rangePart = part;
    if (part.contains('/')) {
      final pieces = part.split('/');
      if (pieces.length != 2) {
        throw FormatException('Invalid step expression "$part"');
      }
      rangePart = pieces[0];
      step = int.parse(pieces[1]);
    }

    Iterable<int> range;
    if (rangePart == '*' || rangePart.isEmpty) {
      range = List<int>.generate(max - min + 1, (i) => min + i);
    } else if (rangePart.contains('-')) {
      final pieces = rangePart.split('-');
      if (pieces.length != 2) {
        throw FormatException('Invalid range expression "$part"');
      }
      final start = _parseValue(pieces[0], min, max, sundayValue);
      final end = _parseValue(pieces[1], min, max, sundayValue);
      if (start > end) {
        throw FormatException('Range start greater than end in "$part"');
      }
      range = List<int>.generate(end - start + 1, (i) => start + i);
    } else {
      final value = _parseValue(rangePart, min, max, sundayValue);
      range = [value];
    }

    final valuesArr = range.toList();
    for (var i = 0; i < valuesArr.length; i += step) {
      target.add(valuesArr[i]);
    }
  }

  /// Parses an individual numeric value within a cron field.
  static int _parseValue(
    String value,
    int min,
    int max, [
    Set<int>? sundayValue,
  ]) {
    final parsedValue = int.tryParse(value);
    if (parsedValue == null) {
      throw FormatException('Invalid cron field value "$value"');
    }
    if (sundayValue != null && sundayValue.contains(parsedValue)) {
      return 0;
    }
    final parsed = parsedValue;
    if (parsed < min || parsed > max) {
      throw RangeError.range(parsed, min, max, 'cron field value');
    }
    return parsed;
  }
}
