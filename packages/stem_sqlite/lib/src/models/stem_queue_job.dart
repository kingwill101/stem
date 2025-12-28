import 'package:ormed/ormed.dart';

part 'stem_queue_job.orm.dart';

@OrmModel(table: 'stem_queue_jobs')
class StemQueueJob extends Model<StemQueueJob> with Timestamps {
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

  @OrmField(isPrimaryKey: true)
  final String id;

  final String queue;

  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;
  final int attempt;

  @OrmField(columnName: 'max_retries')
  final int maxRetries;

  final int priority;

  @OrmField(columnName: 'not_before')
  final DateTime? notBefore;

  @OrmField(columnName: 'locked_at')
  final DateTime? lockedAt;

  @OrmField(columnName: 'locked_until')
  final DateTime? lockedUntil;

  @OrmField(columnName: 'locked_by')
  final String? lockedBy;

}
