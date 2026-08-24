/// A completed PostgreSQL operation measurement.
final class PostgresOperationTiming {
  /// Creates a PostgreSQL operation measurement.
  const PostgresOperationTiming({
    required this.component,
    required this.operation,
    required this.queueWait,
    required this.execution,
    required this.total,
    required this.succeeded,
    this.error,
  });

  /// Component that emitted the operation, such as `broker` or `backend`.
  final String component;

  /// Stable operation name, such as `broker.publish`.
  final String operation;

  /// Time spent waiting for the component's serialized database queue.
  final Duration queueWait;

  /// Time spent executing the database operation.
  final Duration execution;

  /// Total time from enqueueing the operation until it completed.
  final Duration total;

  /// Whether the operation completed successfully.
  final bool succeeded;

  /// A short error description when [succeeded] is false.
  final String? error;

  /// Converts this measurement to an artifact-friendly JSON map.
  Map<String, Object?> toJson() => {
    'component': component,
    'operation': operation,
    'queue_wait_ms': queueWait.inMicroseconds / 1000,
    'execution_ms': execution.inMicroseconds / 1000,
    'total_ms': total.inMicroseconds / 1000,
    'succeeded': succeeded,
    if (error != null) 'error': error,
  };
}

/// Receives completed PostgreSQL operation measurements.
typedef PostgresTimingListener = void Function(PostgresOperationTiming timing);

/// A completed SQL query measurement emitted by the PostgreSQL adapter.
final class PostgresQueryTiming {
  /// Creates a PostgreSQL query measurement.
  const PostgresQueryTiming({
    required this.component,
    required this.sql,
    required this.duration,
    required this.succeeded,
    this.rowCount,
    this.error,
  });

  /// Component that emitted the query, such as `broker` or `backend`.
  final String component;

  /// Parameterized SQL text. Bound values are intentionally not included.
  final String sql;

  /// Time spent executing the query, as reported by Ormed.
  final Duration duration;

  /// Number of rows returned or affected when reported by the driver.
  final int? rowCount;

  /// Whether the query completed successfully.
  final bool succeeded;

  /// A short error description when [succeeded] is false.
  final String? error;

  /// Converts this measurement to an artifact-friendly JSON map.
  Map<String, Object?> toJson() => {
    'component': component,
    'sql': sql,
    'duration_ms': duration.inMicroseconds / 1000,
    if (rowCount != null) 'row_count': rowCount,
    'succeeded': succeeded,
    if (error != null) 'error': error,
  };
}

/// Receives completed SQL query measurements.
typedef PostgresQueryTimingListener = void Function(PostgresQueryTiming query);
