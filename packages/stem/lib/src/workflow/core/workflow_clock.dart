/// Abstraction over time sources used by the workflow runtime and stores.
// Intentionally interface-like for injection and testing.
// ignore: one_member_abstracts
abstract class WorkflowClock {
  /// Creates a workflow clock implementation.
  const WorkflowClock();

  /// Returns the current instant.
  DateTime now();
}

/// Default clock that proxies to [DateTime.now].
class SystemWorkflowClock extends WorkflowClock {
  /// Creates a system clock wrapper.
  const SystemWorkflowClock();

  @override
  DateTime now() => DateTime.now();
}

/// Controllable clock intended for tests.
class FakeWorkflowClock extends WorkflowClock {
  /// Creates a fake clock seeded with [initial].
  FakeWorkflowClock(DateTime initial) : currentTime = initial;

  /// Current time returned by [now].
  DateTime currentTime;

  @override
  DateTime now() => currentTime;

  /// Advances the clock by the given [duration].
  void advance(Duration duration) {
    currentTime = currentTime.add(duration);
  }
}
