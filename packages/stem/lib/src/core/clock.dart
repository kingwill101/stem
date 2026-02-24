import 'dart:async';

/// Shared clock abstraction used across the Stem ecosystem.
abstract class StemClock {
  /// Creates a clock implementation.
  const StemClock();

  /// Returns the current instant.
  DateTime now();
}

/// Default wall-clock implementation.
class SystemStemClock extends StemClock {
  /// Creates a system clock wrapper.
  const SystemStemClock();

  /// Returns the current UTC instant.
  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Controllable clock for deterministic testing.
class FakeStemClock extends StemClock {
  /// Creates a fake clock initialized to [initial].
  FakeStemClock(DateTime initial) : currentTime = initial;

  /// Current instant returned by [now].
  DateTime currentTime;

  @override
  DateTime now() => currentTime;

  /// Advances the fake clock by [duration].
  void advance(Duration duration) {
    currentTime = currentTime.add(duration);
  }
}

final Object _zoneClockKey = Object();
const StemClock _systemClock = SystemStemClock();

/// Returns the current instant from the active clock scope.
DateTime stemNow() {
  final clock = Zone.current[_zoneClockKey];
  if (clock is StemClock) {
    return clock.now();
  }
  return _systemClock.now();
}

/// Runs [body] using [clock] as the active clock for this zone.
T withStemClock<T>(StemClock clock, T Function() body) {
  return runZoned(body, zoneValues: {_zoneClockKey: clock});
}
