import 'package:ormed/ormed.dart';

part 'stem_workflow_watcher.orm.dart';

/// Database model for workflow event watchers.
@OrmModel(table: 'stem_workflow_watchers')
class StemWorkflowWatcher extends Model<StemWorkflowWatcher> {
  /// Creates a workflow watcher record.
  StemWorkflowWatcher({
    required this.runId,
    required this.stepName,
    required this.topic,
    required this.createdAt,
    this.data,
    this.deadline,
  });

  /// Workflow run identifier.
  @OrmField(columnName: 'run_id', isPrimaryKey: true)
  final String runId;

  /// Step name waiting on the event.
  @OrmField(columnName: 'step_name')
  final String stepName;

  /// Event topic to subscribe to.
  @OrmField(columnName: 'topic')
  final String topic;

  /// Optional serialized payload data.
  @OrmField(columnName: 'data')
  final String? data;

  /// Timestamp when the watcher was created.
  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  /// Optional deadline for the watcher.
  @OrmField(columnName: 'deadline')
  final DateTime? deadline;
}
