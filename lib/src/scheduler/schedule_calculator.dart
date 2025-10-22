import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import '../core/contracts.dart';
import 'schedule_spec.dart';
import 'solar_calculator.dart';

class ScheduleCalculator {
  ScheduleCalculator({
    Random? random,
    ScheduleTimezoneResolver? timezoneResolver,
    SolarCalculator? solarCalculator,
  })  : _random = random ?? Random(),
        _timezoneResolver = timezoneResolver,
        _solar = solarCalculator ?? const SolarCalculator();

  final Random _random;
  final ScheduleTimezoneResolver? _timezoneResolver;
  final SolarCalculator _solar;

  DateTime nextRun(
    ScheduleEntry entry,
    DateTime now, {
    bool includeJitter = true,
  }) {
    final spec = entry.spec;
    final tz.Location? location =
        _timezoneResolver?.resolve(entry.timezone);
    final DateTime base = entry.lastRunAt ?? now;
    DateTime next;

    switch (spec) {
      case IntervalScheduleSpec interval:
        next = _nextInterval(interval, base, now);
        break;
      case CronScheduleSpec cron:
        next = _nextCron(cron, base, location);
        break;
      case SolarScheduleSpec solar:
        next = _nextSolar(solar, base, location);
        break;
      case ClockedScheduleSpec clocked:
        next = _nextClocked(clocked, base, now);
        break;
      case CalendarScheduleSpec calendar:
        next = _nextCalendar(calendar, base, location);
        break;
    }

    final jitter = entry.jitter;
    if (includeJitter &&
        jitter != null &&
        jitter > Duration.zero) {
      final jitterMs = _random.nextInt(jitter.inMilliseconds + 1);
      next = next.add(Duration(milliseconds: jitterMs));
    }
    return next;
  }

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
      candidate = candidate.add(Duration(
        milliseconds: (ticks * spec.every.inMilliseconds),
      ));
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
      return runAt.add(Duration(
        milliseconds: now.difference(runAt).inMilliseconds + 1,
      ));
    }
    return runAt;
  }

  DateTime _nextCron(
    CronScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    if (location != null) {
      final tz.TZDateTime localRef = tz.TZDateTime.from(reference, location);
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

    DateTime candidate = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
      reference.hour,
      reference.minute,
    ).add(const Duration(minutes: 1));

    for (var i = 0; i < 525600; i++) {
      if (!_matches(monthField, candidate.month)) {
        candidate = DateTime.utc(candidate.year, candidate.month + 1, 1);
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
        'Unable to compute next run for cron expression $expression');
  }

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

    tz.TZDateTime candidate = tz.TZDateTime(
      location,
      reference.year,
      reference.month,
      reference.day,
      reference.hour,
      reference.minute,
    ).add(const Duration(minutes: 1));

    for (var i = 0; i < 525600; i++) {
      if (!_matches(monthField, candidate.month)) {
        candidate = tz.TZDateTime(location, candidate.year, candidate.month + 1);
        continue;
      }

      if (!_matches(dayField, candidate.day)) {
        candidate = tz.TZDateTime(location, candidate.year, candidate.month,
            candidate.day + 1);
        continue;
      }

      final weekday = candidate.weekday % 7;
      if (!_matchesWeekday(weekdayField, weekday, dayField)) {
        candidate = tz.TZDateTime(location, candidate.year, candidate.month,
            candidate.day + 1);
        continue;
      }

      if (!_matches(hourField, candidate.hour)) {
        candidate = tz.TZDateTime(location, candidate.year, candidate.month,
            candidate.day, candidate.hour + 1);
        continue;
      }

      if (!_matches(minuteField, candidate.minute)) {
        candidate = candidate.add(const Duration(minutes: 1));
        continue;
      }

      return candidate;
    }
    throw StateError(
        'Unable to compute next run for cron expression $expression');
  }

  DateTime _nextCalendar(
    CalendarScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    final cron = CronScheduleSpec(
      expression: _calendarToCron(spec),
    );
    return _nextCron(cron, reference, location);
  }

  DateTime _nextSolar(
    SolarScheduleSpec spec,
    DateTime reference,
    tz.Location? location,
  ) {
    final DateTime start = reference.toUtc();
    final DateTime candidate = _solar.nextEvent(
      spec,
      start,
      location,
    );
    if (spec.offset != null) {
      return candidate.add(spec.offset!);
    }
    return candidate;
  }

  bool _matches(_CronField field, int value) {
    return field.values == null || field.values!.contains(value);
  }

  bool _matchesWeekday(_CronField field, int weekday, _CronField dayField) {
    if (field.values == null) return true;
    if (dayField.values == null) {
      return field.values!.contains(weekday);
    }
    return field.values!.contains(weekday) ||
        dayField.values!.contains(weekday);
  }

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

class _CronField {
  _CronField(this.values);

  final Set<int>? values;

  static _CronField parse(
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

  static void _expandPart(
    String part,
    int min,
    int max,
    Set<int> target, {
    Set<int>? sundayValue,
  }) {
    if (part.isEmpty) {
      throw FormatException('Empty cron field');
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

    final values = range.toList();
    for (var i = 0; i < values.length; i += step) {
      target.add(values[i]);
    }
  }

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
