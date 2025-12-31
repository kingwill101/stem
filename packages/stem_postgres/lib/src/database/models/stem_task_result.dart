import 'package:ormed/ormed.dart';

part 'stem_task_result.orm.dart';

/// Database model for task result records.
@OrmModel(table: 'stem_task_results')
class StemTaskResult extends Model<StemTaskResult> with TimestampsTZ {
  /// Creates a task result record.
  const StemTaskResult({
    required this.id,
    required this.state,
    required this.attempt,
    required this.meta,
    required this.expiresAt,
    this.payload,
    this.error,
  });

  /// Task identifier.
  @OrmField(isPrimaryKey: true)
  final String id;

  /// Task state name.
  final String state;

  /// Task payload stored as JSON.
  @OrmField(cast: 'json')
  final Object? payload;

  /// Task error stored as JSON.
  @OrmField(cast: 'json')
  final Object? error;

  /// Attempt count for the task.
  final int attempt;

  /// Metadata stored with the task result.
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  /// Timestamp when the result expires.
  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;
}
