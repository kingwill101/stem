import 'dart:math' as math;

/// Summarizes repeated benchmark measurements without hiding the raw trials.
final class ThroughputStatistics {
  const ThroughputStatistics._();

  /// Returns summary statistics for [values].
  ///
  /// Percentiles use the nearest-rank method. The returned map is JSON-safe so
  /// it can be embedded directly in a benchmark artifact.
  static Map<String, Object?> summarize(Iterable<num> values) {
    final sorted = values.map((value) => value.toDouble()).toList()..sort();
    if (sorted.isEmpty) {
      return {
        'sample_count': 0,
        'median': null,
        'p5': null,
        'p95': null,
        'minimum': null,
        'maximum': null,
        'mean': null,
        'stddev': null,
        'mad': null,
        'cv': null,
      };
    }

    final median = _median(sorted);
    final mean = sorted.reduce((left, right) => left + right) / sorted.length;
    final variance =
        sorted
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((left, right) => left + right) /
        sorted.length;
    final deviations = sorted.map((value) => (value - median).abs()).toList()
      ..sort();

    return {
      'sample_count': sorted.length,
      'median': median,
      'p5': _percentile(sorted, 0.05),
      'p95': _percentile(sorted, 0.95),
      'minimum': sorted.first,
      'maximum': sorted.last,
      'mean': mean,
      'stddev': math.sqrt(variance),
      'mad': _median(deviations),
      'cv': mean == 0 ? null : math.sqrt(variance) / mean,
    };
  }

  static double _median(List<double> sorted) {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static double _percentile(List<double> sorted, double percentile) {
    final rank = (percentile * sorted.length)
        .ceil()
        .clamp(1, sorted.length)
        .toInt();
    return sorted[rank - 1];
  }
}
