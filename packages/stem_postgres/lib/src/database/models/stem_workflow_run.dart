import 'package:ormed/ormed.dart';

part 'stem_workflow_run.orm.dart';

@OrmModel(table: 'stem_workflow_runs')
class StemWorkflowRun extends Model<StemWorkflowRun> {
  StemWorkflowRun({
    required this.id,
    required this.workflow,
    required this.status,
    required this.params,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.cancellationPolicy,
    this.cancellationData,
    required this.createdAt,
    required this.updatedAt,
  });

  @OrmField(columnName: 'id', isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'workflow')
  final String workflow;

  @OrmField(columnName: 'status')
  final String status;

  @OrmField(columnName: 'params')
  final String params;

  @OrmField(columnName: 'result')
  final String? result;

  @OrmField(columnName: 'wait_topic')
  final String? waitTopic;

  @OrmField(columnName: 'resume_at')
  final DateTime? resumeAt;

  @OrmField(columnName: 'last_error')
  final String? lastError;

  @OrmField(columnName: 'suspension_data')
  final String? suspensionData;

  @OrmField(columnName: 'cancellation_policy')
  final String? cancellationPolicy;

  @OrmField(columnName: 'cancellation_data')
  final String? cancellationData;

  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;
}
