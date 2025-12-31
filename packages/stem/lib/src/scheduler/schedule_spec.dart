import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// Enumerates supported scheduler specification kinds.
class ScheduleSpecKind {
  ScheduleSpecKind._();

  /// Interval-based schedule spec kind.
  static const interval = 'interval';

  /// Cron-based schedule spec kind.
  static const cron = 'cron';

  /// Solar-based schedule spec kind.
  static const solar = 'solar';

  /// Clocked (single timestamp) schedule spec kind.
  static const clocked = 'clocked';

  /// Calendar-based schedule spec kind.
  static const calendar = 'calendar';
}

/// Represents a parsed scheduler specification.
sealed class ScheduleSpec {
  /// Creates a schedule spec with the provided [kind].
  const ScheduleSpec(this.kind);

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

  /// Kind identifier for this spec.
  final String kind;

  /// Serializes this spec to JSON.
  Map<String, Object?> toJson();

  /// Returns a copy of the spec with updated values.
  ScheduleSpec copyWith();
}

/// Schedule specification for fixed intervals.
class IntervalScheduleSpec extends ScheduleSpec {
  /// Creates an interval schedule spec.
  IntervalScheduleSpec({required this.every, this.startAt, this.endAt})
    : super(ScheduleSpecKind.interval) {
    if (every <= Duration.zero) {
      throw ArgumentError.value(
        every,
        'every',
        'Interval duration must be greater than zero.',
      );
    }
  }

  /// Parses a legacy `every:` expression into an interval spec.
  factory IntervalScheduleSpec.fromLegacy(String legacy) {
    final expression = legacy.substring('every:'.length);
    final duration = _parseLegacyDuration(expression.trim());
    return IntervalScheduleSpec(every: duration);
  }

  /// Parses an interval spec from JSON.
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

  /// Interval duration between runs.
  final Duration every;

  /// Optional start timestamp for the interval.
  final DateTime? startAt;

  /// Optional end timestamp for the interval.
  final DateTime? endAt;

  /// Returns a copy of the interval spec with updated values.
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

  /// Serializes the interval spec to JSON.
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

/// Schedule specification for cron expressions.
class CronScheduleSpec extends ScheduleSpec {
  /// Creates a cron schedule spec.
  CronScheduleSpec({
    required this.expression,
    this.description,
    this.secondField,
  }) : assert(expression.trim().isNotEmpty, 'Cron expression must be set.'),
       super(ScheduleSpecKind.cron);

  /// Parses a cron spec from JSON.
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

  /// Cron expression in five-field format.
  final String expression;

  /// Optional human-readable description.
  final String? description;

  /// Optional seconds field for extended cron expressions.
  final String? secondField;

  /// Returns a copy of the cron spec with updated values.
  @override
  CronScheduleSpec copyWith({
    String? expression,
    Object? description = _sentinel,
    Object? secondField = _sentinel,
  }) {
    return CronScheduleSpec(
      expression: expression ?? this.expression,
      description: description == _sentinel
          ? this.description
          : description as String?,
      secondField: secondField == _sentinel
          ? this.secondField
          : secondField as String?,
    );
  }

  /// Serializes the cron spec to JSON.
  /// Serializes the calendar spec to JSON.
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'expression': expression,
    if (description != null) 'description': description,
    if (secondField != null) 'secondField': secondField,
  };
}

/// Schedule specification for solar events.
class SolarScheduleSpec extends ScheduleSpec {
  /// Creates a solar schedule spec.
  SolarScheduleSpec({
    required this.event,
    required this.latitude,
    required this.longitude,
    this.offset,
  }) : assert(
         _validEvents.contains(event),
         'Solar event must be one of $_validEvents',
       ),
       super(ScheduleSpecKind.solar);

  /// Parses a solar spec from JSON.
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

  /// Solar event name (e.g. sunrise, sunset).
  final String event;

  /// Latitude used to compute the solar event.
  final double latitude;

  /// Longitude used to compute the solar event.
  final double longitude;

  /// Optional offset applied to the computed event time.
  final Duration? offset;

  /// Returns a copy of the solar spec with updated values.
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

  /// Serializes the solar spec to JSON.
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

/// Schedule specification for a fixed run timestamp.
class ClockedScheduleSpec extends ScheduleSpec {
  /// Creates a clocked schedule spec.
  ClockedScheduleSpec({required this.runAt, this.runOnce = true})
    : super(ScheduleSpecKind.clocked);

  /// Parses a clocked spec from JSON.
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

  /// Timestamp when the schedule should fire.
  final DateTime runAt;

  /// Whether the schedule should run only once.
  final bool runOnce;

  /// Returns a copy of the clocked spec with updated values.
  @override
  ClockedScheduleSpec copyWith({DateTime? runAt, bool? runOnce}) {
    return ClockedScheduleSpec(
      runAt: runAt ?? this.runAt,
      runOnce: runOnce ?? this.runOnce,
    );
  }

  /// Serializes the clocked spec to JSON.
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'runAt': runAt.toIso8601String(),
    'runOnce': runOnce,
  };
}

/// Schedule specification for calendar fields (months, weekdays, etc.).
class CalendarScheduleSpec extends ScheduleSpec {
  /// Creates a calendar schedule spec.
  CalendarScheduleSpec({
    this.months,
    this.weekdays,
    this.monthdays,
    this.hours,
    this.minutes,
  }) : super(ScheduleSpecKind.calendar);

  /// Parses a calendar spec from JSON.
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

  /// Optional month numbers (1-12).
  final List<int>? months;

  /// Optional weekday numbers (0-6 or 1-7 depending on locale).
  final List<int>? weekdays;

  /// Optional day-of-month values.
  final List<int>? monthdays;

  /// Optional hour values.
  final List<int>? hours;

  /// Optional minute values.
  final List<int>? minutes;

  /// Returns a copy of the calendar spec with updated values.
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
  /// Creates a resolver that uses [_provider] with a default timezone fallback.
  ScheduleTimezoneResolver(this._provider, {String defaultTimezone = 'UTC'})
    : _defaultTimezone = defaultTimezone;

  final tz.Location Function(String name)? _provider;
  final String _defaultTimezone;

  /// Resolves [name] into a timezone location, defaulting when absent.
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
