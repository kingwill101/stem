import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// Enumerates supported scheduler specification kinds.
class ScheduleSpecKind {
  ScheduleSpecKind._();

  static const interval = 'interval';
  static const cron = 'cron';
  static const solar = 'solar';
  static const clocked = 'clocked';
  static const calendar = 'calendar';
}

/// Represents a parsed scheduler specification.
sealed class ScheduleSpec {
  const ScheduleSpec(this.kind);

  final String kind;

  Map<String, Object?> toJson();

  ScheduleSpec copyWith();

  /// Factory that accepts existing persisted representations.
  factory ScheduleSpec.fromPersisted(Object? raw) {
    if (raw == null) {
      throw const FormatException('schedule spec must not be null');
    }
    if (raw is String) {
      if (raw.startsWith('every:')) {
        return IntervalScheduleSpec.fromLegacy(raw);
      }
      return CronScheduleSpec(expression: raw);
    }
    if (raw is Map<String, Object?>) {
      final kind = raw['kind'] as String?;
      switch (kind) {
        case ScheduleSpecKind.interval:
          return IntervalScheduleSpec.fromJson(raw);
        case ScheduleSpecKind.cron:
          return CronScheduleSpec.fromJson(raw);
        case ScheduleSpecKind.solar:
          return SolarScheduleSpec.fromJson(raw);
        case ScheduleSpecKind.clocked:
          return ClockedScheduleSpec.fromJson(raw);
        case ScheduleSpecKind.calendar:
          return CalendarScheduleSpec.fromJson(raw);
      }
      throw FormatException('Unknown schedule spec kind: "$kind"');
    }
    if (raw is String && raw.trim().isEmpty) {
      throw const FormatException('schedule spec must not be empty');
    }
    return CronScheduleSpec(expression: raw.toString());
  }
}

class IntervalScheduleSpec extends ScheduleSpec {
  IntervalScheduleSpec({
    required this.every,
    this.startAt,
    this.endAt,
  }) : super(ScheduleSpecKind.interval) {
    if (every <= Duration.zero) {
      throw ArgumentError.value(
        every,
        'every',
        'Interval duration must be greater than zero.',
      );
    }
  }

  factory IntervalScheduleSpec.fromLegacy(String legacy) {
    final expression = legacy.substring('every:'.length);
    final duration = _parseLegacyDuration(expression.trim());
    return IntervalScheduleSpec(every: duration);
  }

  factory IntervalScheduleSpec.fromJson(Map<String, Object?> json) {
    final everyMs = json['everyMs'] ?? json['every_ms'] ?? json['every'];
    if (everyMs == null) {
      throw const FormatException('interval spec missing "everyMs"');
    }
    final everyDuration = _parseDurationField(everyMs);
    if (everyDuration == null) {
      throw const FormatException('interval spec missing "every" duration');
    }
    return IntervalScheduleSpec(
      every: everyDuration,
      startAt: _parseDate(json['startAt'] ?? json['start_at']),
      endAt: _parseDate(json['endAt'] ?? json['end_at']),
    );
  }

  final Duration every;
  final DateTime? startAt;
  final DateTime? endAt;

  @override
  IntervalScheduleSpec copyWith({
    Duration? every,
    Object? startAt = _sentinel,
    Object? endAt = _sentinel,
  }) {
    return IntervalScheduleSpec(
      every: every ?? this.every,
      startAt: startAt == _sentinel ? this.startAt : startAt as DateTime?,
      endAt: endAt == _sentinel ? this.endAt : endAt as DateTime?,
    );
  }

  @override
  Map<String, Object?> toJson() {
    final startAtValue = startAt;
    final endAtValue = endAt;
    return {
      'kind': kind,
      'everyMs': every.inMilliseconds,
      if (startAtValue != null) 'startAt': startAtValue.toIso8601String(),
      if (endAtValue != null) 'endAt': endAtValue.toIso8601String(),
    };
  }
}

class CronScheduleSpec extends ScheduleSpec {
  CronScheduleSpec({
    required this.expression,
    this.description,
    this.secondField,
  })  : assert(expression.trim().isNotEmpty, 'Cron expression must be set.'),
        super(ScheduleSpecKind.cron);

  factory CronScheduleSpec.fromJson(Map<String, Object?> json) {
    final expression = json['expression'] as String?;
    if (expression == null || expression.trim().isEmpty) {
      throw const FormatException('cron spec missing expression');
    }
    return CronScheduleSpec(
      expression: expression,
      description: json['description'] as String?,
      secondField:
          json['secondField'] as String? ?? json['second_field'] as String?,
    );
  }

  final String expression;
  final String? description;
  final String? secondField;

  @override
  CronScheduleSpec copyWith({
    String? expression,
    Object? description = _sentinel,
    Object? secondField = _sentinel,
  }) {
    return CronScheduleSpec(
      expression: expression ?? this.expression,
      description:
          description == _sentinel ? this.description : description as String?,
      secondField:
          secondField == _sentinel ? this.secondField : secondField as String?,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'expression': expression,
        if (description != null) 'description': description,
        if (secondField != null) 'secondField': secondField,
      };
}

class SolarScheduleSpec extends ScheduleSpec {
  SolarScheduleSpec({
    required this.event,
    required this.latitude,
    required this.longitude,
    this.offset,
  })  : assert(_validEvents.contains(event),
            'Solar event must be one of $_validEvents'),
        super(ScheduleSpecKind.solar);

  factory SolarScheduleSpec.fromJson(Map<String, Object?> json) {
    final event = json['event'] as String?;
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (event == null ||
        latitude == null ||
        longitude == null ||
        !_validEvents.contains(event)) {
      throw const FormatException('Invalid solar schedule spec');
    }
    return SolarScheduleSpec(
      event: event,
      latitude: latitude,
      longitude: longitude,
      offset: _parseDurationField(json['offset']),
    );
  }

  static const Set<String> _validEvents = {'sunrise', 'sunset', 'noon'};

  final String event;
  final double latitude;
  final double longitude;
  final Duration? offset;

  @override
  SolarScheduleSpec copyWith({
    String? event,
    double? latitude,
    double? longitude,
    Object? offset = _sentinel,
  }) {
    return SolarScheduleSpec(
      event: event ?? this.event,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      offset: offset == _sentinel ? this.offset : offset as Duration?,
    );
  }

  @override
  Map<String, Object?> toJson() {
    final offsetValue = offset;
    return {
      'kind': kind,
      'event': event,
      'latitude': latitude,
      'longitude': longitude,
      if (offsetValue != null) 'offsetMs': offsetValue.inMilliseconds,
    };
  }
}

class ClockedScheduleSpec extends ScheduleSpec {
  ClockedScheduleSpec({
    required this.runAt,
    this.runOnce = true,
  }) : super(ScheduleSpecKind.clocked);

  factory ClockedScheduleSpec.fromJson(Map<String, Object?> json) {
    final runAtRaw = json['runAt'] ?? json['run_at'];
    final runAt = _parseDate(runAtRaw);
    if (runAt == null) {
      throw const FormatException('Clocked schedule missing runAt timestamp');
    }
    return ClockedScheduleSpec(
      runAt: runAt,
      runOnce: json['runOnce'] as bool? ?? json['run_once'] as bool? ?? true,
    );
  }

  final DateTime runAt;
  final bool runOnce;

  @override
  ClockedScheduleSpec copyWith({
    DateTime? runAt,
    bool? runOnce,
  }) {
    return ClockedScheduleSpec(
      runAt: runAt ?? this.runAt,
      runOnce: runOnce ?? this.runOnce,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'runAt': runAt.toIso8601String(),
        'runOnce': runOnce,
      };
}

class CalendarScheduleSpec extends ScheduleSpec {
  CalendarScheduleSpec({
    this.months,
    this.weekdays,
    this.monthdays,
    this.hours,
    this.minutes,
  }) : super(ScheduleSpecKind.calendar);

  factory CalendarScheduleSpec.fromJson(Map<String, Object?> json) {
    List<int>? parseIntList(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is List) {
        return raw
            .map((value) => value is num ? value.toInt() : int.parse('$value'))
            .toList();
      }
      throw FormatException('Expected list for calendar spec "$key"');
    }

    return CalendarScheduleSpec(
      months: parseIntList('months'),
      weekdays: parseIntList('weekdays'),
      monthdays: parseIntList('monthdays'),
      hours: parseIntList('hours'),
      minutes: parseIntList('minutes'),
    );
  }

  final List<int>? months;
  final List<int>? weekdays;
  final List<int>? monthdays;
  final List<int>? hours;
  final List<int>? minutes;

  @override
  CalendarScheduleSpec copyWith({
    List<int>? months,
    List<int>? weekdays,
    List<int>? monthdays,
    List<int>? hours,
    List<int>? minutes,
  }) {
    return CalendarScheduleSpec(
      months: months ?? this.months,
      weekdays: weekdays ?? this.weekdays,
      monthdays: monthdays ?? this.monthdays,
      hours: hours ?? this.hours,
      minutes: minutes ?? this.minutes,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        if (months != null) 'months': months,
        if (weekdays != null) 'weekdays': weekdays,
        if (monthdays != null) 'monthdays': monthdays,
        if (hours != null) 'hours': hours,
        if (minutes != null) 'minutes': minutes,
      };
}

/// Lazily resolves timezone identifiers. Exposed for calculators.
class ScheduleTimezoneResolver {
  ScheduleTimezoneResolver(this._provider, {String defaultTimezone = 'UTC'})
      : _defaultTimezone = defaultTimezone;

  final tz.Location Function(String name)? _provider;
  final String _defaultTimezone;

  tz.Location resolve(String? name) {
    final id = (name == null || name.trim().isEmpty) ? _defaultTimezone : name;
    final resolver = _provider;
    if (resolver == null) {
      throw StateError(
        'Timezone support requires timezone data. '
        'Configure ScheduleCalculator with a location provider.',
      );
    }
    return resolver(id);
  }
}

Duration? _parseDurationField(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return Duration(milliseconds: raw.toInt());
  if (raw is String && raw.trim().isNotEmpty) {
    return _parseLegacyDuration(raw.trim());
  }
  return null;
}

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.parse(raw);
  }
  throw FormatException('Invalid date value: ${jsonEncode(raw)}');
}

Duration _parseLegacyDuration(String expression) {
  final regex = RegExp(r'^(\d+)(ms|s|m|h|d)?$');
  final match = regex.firstMatch(expression);
  if (match == null) {
    throw FormatException('Invalid duration expression "$expression"');
  }
  final value = int.parse(match.group(1)!);
  final unit = match.group(2) ?? 's';
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
  throw FormatException('Unsupported duration unit "$unit"');
}

const _sentinel = Object();
