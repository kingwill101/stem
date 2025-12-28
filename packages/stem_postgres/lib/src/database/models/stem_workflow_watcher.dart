import 'package:ormed/ormed.dart';

part 'stem_workflow_watcher.orm.dart';

@OrmModel(table: 'stem_workflow_watchers')
class StemWorkflowWatcher extends Model<StemWorkflowWatcher> {
  StemWorkflowWatcher({
    required this.runId,
    required this.stepName,
    required this.topic,
    this.data,
    required this.createdAt,
    this.deadline,
  });

  @OrmField(columnName: 'run_id', isPrimaryKey: true)
  final String runId;

  @OrmField(columnName: 'step_name')
  final String stepName;

  @OrmField(columnName: 'topic')
  final String topic;

  @OrmField(columnName: 'data')
  final String? data;

  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  @OrmField(columnName: 'deadline')
  final DateTime? deadline;
}
