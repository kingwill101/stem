import 'package:ormed/ormed.dart';

part 'stem_schedule_entry.orm.dart';

/// Database model for scheduled task entries.
@OrmModel(table: 'stem_schedules')
class StemScheduleEntry extends Model<StemScheduleEntry> {
  /// Creates a schedule entry record.
  StemScheduleEntry({
    required this.id,
    required this.namespace,
    required this.taskName,
    required this.queue,
    required this.spec,
    required this.createdAt,
    required this.updatedAt,
    this.args,
    this.kwargs,
    this.enabled = true,
    this.jitter,
    this.lastRunAt,
    this.nextRunAt,
    this.lastJitter,
    this.lastError,
    this.timezone,
    this.totalRunCount = 0,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.drift,
    this.expireAt,
    this.meta,
    this.version = 0,
  });

  /// Schedule identifier.
  @OrmField(columnName: 'id', isPrimaryKey: true)
  final String id;

  /// Namespace that owns the schedule entry.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Task name to execute.
  @OrmField(columnName: 'task_name')
  final String taskName;

  /// Queue name for the task.
  @OrmField(columnName: 'queue')
  final String queue;

  /// Cron or interval specification.
  @OrmField(columnName: 'spec')
  final String spec;

  /// Serialized positional arguments.
  @OrmField(columnName: 'args')
  final String? args;

  /// Serialized keyword arguments.
  @OrmField(columnName: 'kwargs')
  final String? kwargs;

  /// Whether the schedule is enabled.
  @OrmField(columnName: 'enabled')
  final bool enabled;

  /// Optional jitter applied to the schedule.
  @OrmField(columnName: 'jitter')
  final int? jitter;

  /// Timestamp of the last execution.
  @OrmField(columnName: 'last_run_at')
  final DateTime? lastRunAt;

  /// Timestamp of the next scheduled execution.
  @OrmField(columnName: 'next_run_at')
  final DateTime? nextRunAt;

  /// Jitter applied to the last run.
  @OrmField(columnName: 'last_jitter')
  final int? lastJitter;

  /// Last error message recorded.
  @OrmField(columnName: 'last_error')
  final String? lastError;

  /// Timezone identifier used for scheduling.
  @OrmField(columnName: 'timezone')
  final String? timezone;

  /// Total number of runs recorded.
  @OrmField(columnName: 'total_run_count')
  final int totalRunCount;

  /// Timestamp of the last successful run.
  @OrmField(columnName: 'last_success_at')
  final DateTime? lastSuccessAt;

  /// Timestamp of the last failed run.
  @OrmField(columnName: 'last_error_at')
  final DateTime? lastErrorAt;

  /// Drift in seconds between scheduled and actual run.
  @OrmField(columnName: 'drift')
  final int? drift;

  /// Optional expiration time for the schedule.
  @OrmField(columnName: 'expire_at')
  final DateTime? expireAt;

  /// Optional metadata stored with the schedule.
  @OrmField(columnName: 'meta')
  final String? meta;

  /// Timestamp when the record was created.
  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  /// Timestamp when the record was last updated.
  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;

  /// Version counter for optimistic updates.
  @OrmField(columnName: 'version')
  final int? version;
}
