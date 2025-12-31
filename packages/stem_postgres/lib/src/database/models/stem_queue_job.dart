import 'package:ormed/ormed.dart';

part 'stem_queue_job.orm.dart';

/// Database model for queued jobs.
@OrmModel(table: 'stem_queue_jobs')
class StemQueueJob extends Model<StemQueueJob> with TimestampsTZ {
  /// Creates a queue job record.
  const StemQueueJob({
    required this.id,
    required this.queue,
    required this.envelope,
    required this.attempt,
    required this.maxRetries,
    required this.priority,
    this.notBefore,
    this.lockedAt,
    this.lockedUntil,
    this.lockedBy,
  });

  /// Job identifier.
  @OrmField(isPrimaryKey: true)
  final String id;

  /// Queue name.
  final String queue;

  /// Envelope payload stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;

  /// Attempt count for the job.
  final int attempt;

  /// Maximum retry count for the job.
  @OrmField(columnName: 'max_retries')
  final int maxRetries;

  /// Priority assigned to the job.
  final int priority;

  /// Timestamp before which the job should not be visible.
  @OrmField(columnName: 'not_before')
  final DateTime? notBefore;

  /// Timestamp when the job was locked for processing.
  @OrmField(columnName: 'locked_at')
  final DateTime? lockedAt;

  /// Timestamp when the lock expires.
  @OrmField(columnName: 'locked_until')
  final DateTime? lockedUntil;

  /// Worker identifier holding the lock.
  @OrmField(columnName: 'locked_by')
  final String? lockedBy;
}
