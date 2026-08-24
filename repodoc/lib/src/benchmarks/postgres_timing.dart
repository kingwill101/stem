import 'dart:collection';
import 'dart:math';

import 'package:stem_postgres/stem_postgres.dart';

/// Aggregates PostgreSQL adapter timings for a benchmark report.
///
/// Operation names are expected to be low-cardinality. SQL statements are
/// retained only for the most recently observed [maxQueryKeys] groups, and
/// each group keeps a bounded reservoir sample for percentile calculations.
final class PostgresTimingCollector {
  PostgresTimingCollector({this.sampleSize = 256, this.maxQueryKeys = 1024}) {
    if (sampleSize <= 0) {
      throw ArgumentError.value(sampleSize, 'sampleSize');
    }
    if (maxQueryKeys <= 0) {
      throw ArgumentError.value(maxQueryKeys, 'maxQueryKeys');
    }
  }

  /// Number of measurements retained per aggregate for p95 estimation.
  final int sampleSize;

  /// Maximum number of distinct SQL component/statement groups retained.
  final int maxQueryKeys;

  final Map<String, _OperationAggregate> _byOperation = {};
  final LinkedHashMap<String, _QueryAggregate> _byQuery = LinkedHashMap();
  final Random _random = Random(0);

  /// Records one completed operation.
  void add(PostgresOperationTiming timing) {
    final aggregate = _byOperation.putIfAbsent(
      timing.operation,
      _OperationAggregate.new,
    );
    aggregate.add(timing, sampleSize: sampleSize, random: _random);
  }

  /// Records one completed SQL query.
  void addQuery(PostgresQueryTiming timing) {
    final key = '${timing.component}\u0000${timing.sql}';
    var aggregate = _byQuery[key];
    if (aggregate == null) {
      if (_byQuery.length >= maxQueryKeys) {
        _byQuery.remove(_byQuery.keys.first);
      }
      aggregate = _QueryAggregate(component: timing.component, sql: timing.sql);
    } else {
      // Keep the eviction order aligned with the most recently observed SQL
      // groups while retaining the existing aggregate and its sample.
      _byQuery.remove(key);
    }
    _byQuery[key] = aggregate;
    aggregate.add(timing, sampleSize: sampleSize, random: _random);
  }

  /// Returns one aggregate row per operation.
  List<Map<String, Object?>> toJson() {
    final rows = [
      for (final entry in _byOperation.entries) entry.value.toJson(entry.key),
    ];
    rows.sort(
      (a, b) =>
          (a['operation']! as String).compareTo(b['operation']! as String),
    );
    return rows;
  }

  /// Returns aggregate rows for the bounded set of SQL queries observed.
  List<Map<String, Object?>> queryJson() {
    final rows = [for (final aggregate in _byQuery.values) aggregate.toJson()];
    rows.sort((a, b) => (b['max_ms']! as num).compareTo(a['max_ms']! as num));
    return rows;
  }
}

final class _OperationAggregate {
  final _TimingAggregate total = _TimingAggregate();
  final _TimingAggregate execution = _TimingAggregate();
  final _TimingAggregate queueWait = _TimingAggregate();

  void add(
    PostgresOperationTiming timing, {
    required int sampleSize,
    required Random random,
  }) {
    total.add(
      timing.total.inMicroseconds / 1000,
      succeeded: timing.succeeded,
      sampleSize: sampleSize,
      random: random,
    );
    execution.add(
      timing.execution.inMicroseconds / 1000,
      succeeded: timing.succeeded,
      sampleSize: sampleSize,
      random: random,
    );
    queueWait.add(
      timing.queueWait.inMicroseconds / 1000,
      succeeded: timing.succeeded,
      sampleSize: sampleSize,
      random: random,
    );
  }

  Map<String, Object?> toJson(String operation) => {
    'operation': operation,
    'count': total.count,
    'failures': total.failures,
    'avg_ms': total.average,
    'p95_ms': total.p95,
    'max_ms': total.maximum,
    'avg_execution_ms': execution.average,
    'avg_queue_wait_ms': queueWait.average,
  };
}

final class _QueryAggregate {
  _QueryAggregate({required this.component, required this.sql});

  final String component;
  final String sql;
  final _TimingAggregate duration = _TimingAggregate();

  void add(
    PostgresQueryTiming timing, {
    required int sampleSize,
    required Random random,
  }) {
    duration.add(
      timing.duration.inMicroseconds / 1000,
      succeeded: timing.succeeded,
      sampleSize: sampleSize,
      random: random,
    );
  }

  Map<String, Object?> toJson() => {
    'component': component,
    'sql': sql,
    'count': duration.count,
    'failures': duration.failures,
    'avg_ms': duration.average,
    'p95_ms': duration.p95,
    'max_ms': duration.maximum,
  };
}

final class _TimingAggregate {
  int count = 0;
  int failures = 0;
  double sum = 0;
  double maximum = 0;
  int _sampleCount = 0;
  final List<double> _sample = [];

  double get average => count == 0 ? 0 : sum / count;

  double get p95 {
    if (_sample.isEmpty) return 0;
    final sorted = List<double>.from(_sample)..sort();
    return sorted[_percentileIndex(sorted.length, 0.95)];
  }

  void add(
    double value, {
    required bool succeeded,
    required int sampleSize,
    required Random random,
  }) {
    count += 1;
    if (!succeeded) failures += 1;
    sum += value;
    if (value > maximum) maximum = value;

    _sampleCount += 1;
    if (_sample.length < sampleSize) {
      _sample.add(value);
      return;
    }
    final replacement = random.nextInt(_sampleCount);
    if (replacement < sampleSize) {
      _sample[replacement] = value;
    }
  }
}

int _percentileIndex(int length, double percentile) {
  return ((length * percentile).ceil() - 1).clamp(0, length - 1).toInt();
}
