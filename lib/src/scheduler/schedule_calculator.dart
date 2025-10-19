import 'dart:math';

import '../core/contracts.dart';

class ScheduleCalculator {
  ScheduleCalculator({Random? random}) : _random = random ?? Random();

  final Random _random;

  DateTime nextRun(
    ScheduleEntry entry,
    DateTime now, {
    bool includeJitter = true,
  }) {
    final base = entry.lastRunAt ?? now;
    final nextBase = _calculateNextTimestamp(entry.spec, base);
    if (includeJitter &&
        entry.jitter != null &&
        entry.jitter! > Duration.zero) {
      final jitterMs = _random.nextInt(entry.jitter!.inMilliseconds + 1);
      return nextBase.add(Duration(milliseconds: jitterMs));
    }
    return nextBase;
  }

  DateTime _calculateNextTimestamp(String spec, DateTime from) {
    if (spec.startsWith('every:')) {
      final duration = _parseEvery(spec.substring(6));
      final base = from.isUtc
          ? from
          : from.toUtc(); // ensure consistent arithmetic
      return base.add(duration).toLocal();
    }
    return _nextCron(spec, from);
  }

  Duration _parseEvery(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Invalid every: expression: "$expression"');
    }
    final unitMatch = RegExp(r'^(\d+)(ms|s|m|h|d)?$').firstMatch(trimmed);
    if (unitMatch == null) {
      throw FormatException('Invalid every: expression: "$expression"');
    }
    final value = int.parse(unitMatch.group(1)!);
    final unit = unitMatch.group(2) ?? 's';
    switch (unit) {
      case 'ms':
        return Duration(milliseconds: value);
      case 's':
        return Duration(seconds: value);
      case 'm':
        return Duration(minutes: value);
      case 'h':
        return Duration(hours: value);
      case 'd':
        return Duration(days: value);
    }
    throw FormatException('Unknown duration unit: "$unit"');
  }

  DateTime _nextCron(String expression, DateTime start) {
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

    var candidate = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    ).add(const Duration(minutes: 1));

    for (var i = 0; i < 525600; i++) {
      if (!_matches(monthField, candidate.month)) {
        candidate = DateTime(candidate.year, candidate.month + 1, 1, 0, 0);
        continue;
      }

      if (!_matches(dayField, candidate.day)) {
        candidate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day + 1,
          0,
          0,
        );
        continue;
      }

      final weekday = (candidate.weekday % 7);
      if (!_matchesWeekday(weekdayField, weekday, dayField)) {
        candidate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day + 1,
          0,
          0,
        );
        continue;
      }

      if (!_matches(hourField, candidate.hour)) {
        candidate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour + 1,
          0,
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
