import 'package:stem_postgres/stem_postgres.dart';

/// Aggregates PostgreSQL adapter timings for a benchmark report.
final class PostgresTimingCollector {
  final Map<String, List<PostgresOperationTiming>> _byOperation = {};
  final Map<String, List<PostgresQueryTiming>> _byQuery = {};

  /// Records one completed operation.
  void add(PostgresOperationTiming timing) {
    (_byOperation[timing.operation] ??= []).add(timing);
  }

  /// Records one completed SQL query.
  void addQuery(PostgresQueryTiming timing) {
    final key = '${timing.component}\u0000${timing.sql}';
    (_byQuery[key] ??= []).add(timing);
  }

  /// Returns one aggregate row per operation.
  List<Map<String, Object?>> toJson() {
    final rows = <Map<String, Object?>>[];
    for (final entry in _byOperation.entries) {
      final timings = [...entry.value]
        ..sort((a, b) => a.total.compareTo(b.total));
      final totalMs = timings
          .map((timing) => timing.total.inMicroseconds / 1000)
          .toList(growable: false);
      final executionMs = timings
          .map((timing) => timing.execution.inMicroseconds / 1000)
          .toList(growable: false);
      final queueWaitMs = timings
          .map((timing) => timing.queueWait.inMicroseconds / 1000)
          .toList(growable: false);
      final failures = timings.where((timing) => !timing.succeeded).length;
      rows.add({
        'operation': entry.key,
        'count': timings.length,
        'failures': failures,
        'avg_ms': _average(totalMs),
        'p95_ms': _percentile(totalMs, 0.95),
        'max_ms': totalMs.last,
        'avg_execution_ms': _average(executionMs),
        'avg_queue_wait_ms': _average(queueWaitMs),
      });
    }
    rows.sort(
      (a, b) =>
          (a['operation']! as String).compareTo(b['operation']! as String),
    );
    return rows;
  }

  /// Returns aggregate rows for the SQL queries observed during the run.
  List<Map<String, Object?>> queryJson() {
    final rows = <Map<String, Object?>>[];
    for (final timings in _byQuery.values) {
      final sorted = [...timings]
        ..sort((a, b) => a.duration.compareTo(b.duration));
      final durations = sorted
          .map((timing) => timing.duration.inMicroseconds / 1000)
          .toList(growable: false);
      rows.add({
        'component': sorted.first.component,
        'sql': sorted.first.sql,
        'count': sorted.length,
        'failures': sorted.where((timing) => !timing.succeeded).length,
        'avg_ms': _average(durations),
        'p95_ms': _percentile(durations, 0.95),
        'max_ms': durations.last,
      });
    }
    rows.sort((a, b) => (b['max_ms']! as num).compareTo(a['max_ms']! as num));
    return rows;
  }
}

double _average(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) return 0;
  final index = ((sortedValues.length * percentile).ceil() - 1).clamp(
    0,
    sortedValues.length - 1,
  );
  return sortedValues[index];
}
