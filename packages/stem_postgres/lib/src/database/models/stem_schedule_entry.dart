import 'package:ormed/ormed.dart';

part 'stem_schedule_entry.orm.dart';

@OrmModel(table: 'stem_schedules')
class StemScheduleEntry extends Model<StemScheduleEntry> {
  StemScheduleEntry({
    required this.id,
    required this.taskName,
    required this.queue,
    required this.spec,
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
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
  });

  @OrmField(columnName: 'id', isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'task_name')
  final String taskName;

  @OrmField(columnName: 'queue')
  final String queue;

  @OrmField(columnName: 'spec')
  final String spec;

  @OrmField(columnName: 'args')
  final String? args;

  @OrmField(columnName: 'kwargs')
  final String? kwargs;

  @OrmField(columnName: 'enabled')
  final bool enabled;

  @OrmField(columnName: 'jitter')
  final int? jitter;

  @OrmField(columnName: 'last_run_at')
  final DateTime? lastRunAt;

  @OrmField(columnName: 'next_run_at')
  final DateTime? nextRunAt;

  @OrmField(columnName: 'last_jitter')
  final int? lastJitter;

  @OrmField(columnName: 'last_error')
  final String? lastError;

  @OrmField(columnName: 'timezone')
  final String? timezone;

  @OrmField(columnName: 'total_run_count')
  final int totalRunCount;

  @OrmField(columnName: 'last_success_at')
  final DateTime? lastSuccessAt;

  @OrmField(columnName: 'last_error_at')
  final DateTime? lastErrorAt;

  @OrmField(columnName: 'drift')
  final int? drift;

  @OrmField(columnName: 'expire_at')
  final DateTime? expireAt;

  @OrmField(columnName: 'meta')
  final String? meta;

  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;

  @OrmField(columnName: 'version')
  final int? version;
}
