/// Abstraction over time sources used by the workflow runtime and stores.
abstract class WorkflowClock {
  const WorkflowClock();

  /// Returns the current instant.
  DateTime now();
}

/// Default clock that proxies to [DateTime.now].
class SystemWorkflowClock extends WorkflowClock {
  const SystemWorkflowClock();

  @override
  DateTime now() => DateTime.now();
}

/// Controllable clock intended for tests.
class FakeWorkflowClock extends WorkflowClock {
  FakeWorkflowClock(DateTime initial) : _now = initial;

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Advances the clock by the given [duration].
  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  /// Sets the current time to [value].
  set currentTime(DateTime value) => _now = value;
}
