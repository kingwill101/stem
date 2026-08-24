/// Workload shape used by the throughput benchmark.
enum ThroughputMode {
  /// Enqueue while a worker is consuming the same queue.
  steadyState('steady-state'),

  /// Measure publication only. The measured tasks are not consumed.
  enqueueOnly('enqueue-only'),

  /// Prefill the queue, then measure the worker draining it.
  prefilledDrain('prefilled-drain');

  const ThroughputMode(this.name);

  final String name;

  static ThroughputMode parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'steady' || 'steady-state' => steadyState,
      'enqueue' || 'enqueue-only' => enqueueOnly,
      'drain' || 'prefilled-drain' || 'worker-drain' => prefilledDrain,
      _ => throw ArgumentError(
        'Unsupported benchmark mode "$value". Expected '
        'steady-state, enqueue-only, or prefilled-drain.',
      ),
    };
  }
}
