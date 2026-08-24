/// Task lifecycle path exercised by a throughput benchmark.
enum ThroughputScenario {
  /// Execute successfully and acknowledge normally.
  success('success'),

  /// Request one immediate retry, then succeed on the next attempt.
  retry('retry'),

  /// Fail once and require the worker to move the delivery to the dead-letter
  /// queue.
  deadLetter('dead-letter'),

  /// Explicitly extend the delivery lease before completing the task.
  lease('lease');

  const ThroughputScenario(this.name);

  final String name;

  static ThroughputScenario parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'success' || 'ack' => success,
      'retry' || 'nack' || 'requeue' => retry,
      'dead-letter' || 'deadletter' || 'dlq' => deadLetter,
      'lease' || 'renewal' || 'extend-lease' => lease,
      _ => throw ArgumentError(
        'Unsupported benchmark scenario "$value". Expected '
        'success, retry, dead-letter, or lease.',
      ),
    };
  }
}
