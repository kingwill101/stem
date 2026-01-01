/// Controls how the workflow runtime auto-cancels runs.
///
/// Policies are persisted with the run and evaluated by the runtime whenever
/// a run suspends or before each step is executed. Limits apply per run and do
/// not prevent manual cancellation.
class WorkflowCancellationPolicy {
  /// Creates a cancellation policy for a workflow run.
  const WorkflowCancellationPolicy({
    this.maxRunDuration,
    this.maxSuspendDuration,
  });

  /// Maximum wall-clock time the workflow may run before being cancelled.
  final Duration? maxRunDuration;

  /// Maximum duration a single suspension (sleep/event wait) may last.
  final Duration? maxSuspendDuration;

  /// Whether no limits are configured.
  bool get isEmpty => maxRunDuration == null && maxSuspendDuration == null;

  /// Serializes this policy to JSON.
  Map<String, Object?> toJson() => {
    if (maxRunDuration != null)
      'maxRunDuration': maxRunDuration!.inMilliseconds,
    if (maxSuspendDuration != null)
      'maxSuspendDuration': maxSuspendDuration!.inMilliseconds,
  };

  /// Parses a cancellation policy from JSON.
  static WorkflowCancellationPolicy? fromJson(Object? source) {
    if (source == null) return null;
    if (source is WorkflowCancellationPolicy) return source;
    if (source is! Map) return null;
    Duration? parseDuration(Object? value) {
      if (value == null) return null;
      if (value is int) return Duration(milliseconds: value);
      if (value is num) return Duration(milliseconds: value.toInt());
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return Duration(milliseconds: parsed);
        }
      }
      return null;
    }

    final map = source.cast<String, Object?>();
    final run = parseDuration(map['maxRunDuration']);
    final suspend = parseDuration(map['maxSuspendDuration']);
    if (run == null && suspend == null) {
      return const WorkflowCancellationPolicy();
    }
    return WorkflowCancellationPolicy(
      maxRunDuration: run,
      maxSuspendDuration: suspend,
    );
  }

  /// Returns a copy of this policy with updated values.
  WorkflowCancellationPolicy copyWith({
    Duration? maxRunDuration,
    Duration? maxSuspendDuration,
  }) {
    return WorkflowCancellationPolicy(
      maxRunDuration: maxRunDuration ?? this.maxRunDuration,
      maxSuspendDuration: maxSuspendDuration ?? this.maxSuspendDuration,
    );
  }
}
