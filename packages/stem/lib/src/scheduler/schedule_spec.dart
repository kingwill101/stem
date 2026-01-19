/// Scheduler specification system for the `stem` package.
///
/// This library provides a polymorphic [ScheduleSpec] hierarchy for defining
/// various types of recurring and one-off task schedules.
///
/// ## Schedule Types
///
/// - [IntervalScheduleSpec]: Fixed time intervals (e.g., every 5 minutes).
/// - [CronScheduleSpec]: Standard 5-field cron expressions.
/// - [SolarScheduleSpec]: Astronomical events (sunrise, sunset, noon).
/// - [ClockedScheduleSpec]: Single-use or repeating specific timestamps.
/// - [CalendarScheduleSpec]: Selective calendar matching (months, weekdays).
///
/// ## Configuration & Persistence
///
/// All specifications support JSON serialization via [ScheduleSpec.toJson]
/// and can be reconstructed using [ScheduleSpec.fromPersisted].
///
/// See also:
/// - `ScheduleCalculator` for runtime calculation of next run times.
library;

import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// Enumerates supported scheduler specification kinds.
///
/// These string constants are used in the JSON `kind` field to identify
/// the polymorphic type of a schedule specification.
class ScheduleSpecKind {
  /// Private constructor to prevent instantiation.
  ScheduleSpecKind._();

  /// Interval-based schedule spec kind (`interval`).
  static const interval = 'interval';

  /// Cron-based schedule spec kind (`cron`).
  static const cron = 'cron';

  /// Solar-based schedule spec kind (`solar`).
  static const solar = 'solar';

  /// Clocked (single timestamp) schedule spec kind (`clocked`).
  static const clocked = 'clocked';

  /// Calendar-based schedule spec kind (`calendar`).
  static const calendar = 'calendar';
}

/// Base class for all scheduler specifications.
///
/// A schedule specification defines *when* a task should repeat, but does
/// not store state. State and execution history are managed by `ScheduleEntry`.
sealed class ScheduleSpec {
  /// Internal constructor for schedule specifications.
  const ScheduleSpec(this.kind);

  /// Reconstructs a schedule specification from a persisted representation.
  ///
  /// ## Implementation Details
  ///
  /// This factory supports multiple input formats to ensure backward
  /// compatibility and ease of use:
  ///
  /// 1. **Legacy Strings**:
  ///    - Starts with `every:` → [IntervalScheduleSpec]
  ///    - Otherwise → [CronScheduleSpec]
  ///
  /// 2. **JSON Maps**:
  ///    - Dispatched based on the `kind` field to the appropriate subclass.
  ///
  /// 3. **Empty/Null**: Throws [FormatException].
  ///
  /// ## Throws
  /// - [FormatException] if the kind is unknown or input is invalid.
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

  /// The discriminator kind for this specification.
  final String kind;

  /// Serializes the specification into a JSON-compatible map.
  Map<String, Object?> toJson();

  /// Creates a copy of this specification with optional overrides.
  ScheduleSpec copyWith();
}

/// Schedule specification for fixed time intervals.
///
/// Fires every time the specified [every] duration passes.
class IntervalScheduleSpec extends ScheduleSpec {
  /// Creates an interval-based schedule.
  ///
  /// [every] must be greater than zero.
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

  /// Parses a legacy `every:` expression.
  ///
  /// Example: `every:5m`, `every:1h`
  factory IntervalScheduleSpec.fromLegacy(String legacy) {
    final expression = legacy.substring('every:'.length);
    final duration = _parseLegacyDuration(expression.trim());
    return IntervalScheduleSpec(every: duration);
  }

  /// Reconstructs an interval spec from a JSON map.
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

  /// The duration between consecutive runs.
  final Duration every;

  /// Optional absolute timestamp when this schedule starts being active.
  /// If provided, calculation of intervals will be relative to this date.
  final DateTime? startAt;

  /// Optional absolute timestamp after which this schedule ceases to fire.
  final DateTime? endAt;

  /// Returns a copy of the specification with optional field overrides.
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
  /// Serializes this interval schedule to JSON-friendly data.
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

/// Schedule specification for standard Cron expressions.
///
/// Supports standard 5-field cron strings (minute, hour, day, month, weekday).
class CronScheduleSpec extends ScheduleSpec {
  /// Creates a cron-based schedule.
  CronScheduleSpec({
    required this.expression,
    this.description,
    this.secondField,
  }) : assert(expression.trim().isNotEmpty, 'Cron expression must be set.'),
       super(ScheduleSpecKind.cron);

  /// Reconstructs a cron spec from a JSON map.
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

  /// The raw cron expression (e.g., `0 12 * * *`).
  final String expression;

  /// Optional user-provided description of the schedule.
  final String? description;

  /// Optional metadata field for expressions that include a seconds component.
  final String? secondField;

  @override
  /// Returns a copy of this cron schedule with optional overrides.
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

  @override
  /// Serializes this cron schedule to JSON-friendly data.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'expression': expression,
    if (description != null) 'description': description,
    if (secondField != null) 'secondField': secondField,
  };
}

/// Schedule specification based on celestial/solar events.
///
/// Computes schedule times using geographic coordinates and solar position.
class SolarScheduleSpec extends ScheduleSpec {
  /// Creates a solar-based schedule.
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

  /// Reconstructs a solar spec from a JSON map.
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

  /// The solar event to track (`sunrise`, `sunset`, or `noon`).
  final String event;

  /// Latitude of the target location (-90 to 90).
  final double latitude;

  /// Longitude of the target location (-180 to 180).
  final double longitude;

  /// Optional relative time offset from the computed event.
  ///
  /// Example: `Duration(minutes: -30)` for "30 minutes before sunrise".
  final Duration? offset;

  @override
  /// Returns a copy of this solar schedule with optional overrides.
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
  /// Serializes this solar schedule to JSON-friendly data.
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

/// Schedule specification for a fixed, absolute run time.
class ClockedScheduleSpec extends ScheduleSpec {
  /// Creates a clocked schedule.
  ClockedScheduleSpec({required this.runAt, this.runOnce = true})
    : super(ScheduleSpecKind.clocked);

  /// Reconstructs a clocked spec from a JSON map.
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

  /// The exact time when the task should fire.
  final DateTime runAt;

  /// Whether the task should only run exactly once.
  /// If false, it acts like an interval with a single datum.
  final bool runOnce;

  @override
  /// Returns a copy of this clocked schedule with optional overrides.
  ClockedScheduleSpec copyWith({DateTime? runAt, bool? runOnce}) {
    return ClockedScheduleSpec(
      runAt: runAt ?? this.runAt,
      runOnce: runOnce ?? this.runOnce,
    );
  }

  @override
  /// Serializes this clocked schedule to JSON-friendly data.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'runAt': runAt.toIso8601String(),
    'runOnce': runOnce,
  };
}

/// Schedule specification that matches specific calendar attributes.
///
/// If a list is null, it acts as a wildcard (matches everything).
class CalendarScheduleSpec extends ScheduleSpec {
  /// Creates a calendar-attribute based schedule.
  CalendarScheduleSpec({
    this.months,
    this.weekdays,
    this.monthdays,
    this.hours,
    this.minutes,
  }) : super(ScheduleSpecKind.calendar);

  /// Reconstructs a calendar spec from a JSON map.
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

  /// Specific month numbers (1-12). Wildcard if null.
  final List<int>? months;

  /// Specific weekday numbers (0-6). Wildcard if null.
  final List<int>? weekdays;

  /// Specific days of the month (1-31). Wildcard if null.
  final List<int>? monthdays;

  /// Specific hours of the day (0-23). Wildcard if null.
  final List<int>? hours;

  /// Specific minutes of the hour (0-59). Wildcard if null.
  final List<int>? minutes;

  @override
  /// Returns a copy of this calendar schedule with optional overrides.
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
  /// Serializes this calendar schedule to JSON-friendly data.
  Map<String, Object?> toJson() => {
    'kind': kind,
    if (months != null) 'months': months,
    if (weekdays != null) 'weekdays': weekdays,
    if (monthdays != null) 'monthdays': monthdays,
    if (hours != null) 'hours': hours,
    if (minutes != null) 'minutes': minutes,
  };
}

/// Lazily resolves timezone identifiers.
///
/// Used by schedule calculators to map schedule timezone names into
/// [tz.Location] objects while providing fallbacks and handling aliases.
class ScheduleTimezoneResolver {
  /// Creates a resolver.
  ///
  /// [_provider] is typically `tz.getLocation`.
  ScheduleTimezoneResolver(this._provider, {String defaultTimezone = 'UTC'})
    : _defaultTimezone = defaultTimezone;

  final tz.Location Function(String name)? _provider;
  final String _defaultTimezone;

  /// Resolves [name] into a [tz.Location].
  ///
  /// ## Logic
  ///
  /// 1. Use the default timezone if [name] is empty or null.
  /// 2. Attempt direct resolution via [_provider].
  /// 3. If "UTC" fails, try "Etc/UTC" as an alias.
  /// 4. If "Etc/UTC" fails, try "UTC" as an alias.
  ///
  /// ## Throws
  /// - [StateError] if no timezone provider is configured.
  tz.Location resolve(String? name) {
    final id = (name == null || name.trim().isEmpty) ? _defaultTimezone : name;
    final resolver = _provider;
    if (resolver == null) {
      throw StateError(
        'Timezone support requires timezone data. '
        'Configure ScheduleCalculator with a location provider.',
      );
    }
    try {
      return resolver(id);
    } on Exception {
      if (id == 'UTC') {
        return resolver('Etc/UTC');
      }
      if (id == 'Etc/UTC') {
        return resolver('UTC');
      }
      rethrow;
    }
  }
}

/// Internal helper to parse flexible duration fields from JSON.
Duration? _parseDurationField(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return Duration(milliseconds: raw.toInt());
  if (raw is String && raw.trim().isNotEmpty) {
    return _parseLegacyDuration(raw.trim());
  }
  return null;
}

/// Internal helper to parse absolute dates from JSON/Metadata.
DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.parse(raw);
  }
  throw FormatException('Invalid date value: ${jsonEncode(raw)}');
}

/// Logic for parsing shorthand duration strings.
///
/// Supported units: `ms`, `s`, `m`, `h`, `d`.
/// Example: `30s`, `1h`, `500ms`.
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
