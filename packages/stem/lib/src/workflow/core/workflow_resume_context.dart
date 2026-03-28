import 'dart:async';

/// Shared suspension/resume surface implemented by flow steps and script
/// checkpoints.
///
/// This keeps typed event wait helpers on a single workflow-facing capability
/// instead of accepting an erased `Object` and branching at runtime.
abstract interface class WorkflowResumeContext {
  /// Returns and clears the resume payload supplied by the runtime.
  Object? takeResumeData();

  /// Schedules a durable wake-up after [duration].
  FutureOr<void> suspendFor(
    Duration duration, {
    Map<String, Object?>? data,
  });

  /// Suspends until [topic] is emitted.
  FutureOr<void> waitForTopic(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  });
}
