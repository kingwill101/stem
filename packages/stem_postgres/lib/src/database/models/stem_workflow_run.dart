import 'package:ormed/ormed.dart';

part 'stem_workflow_run.orm.dart';

/// Database model for workflow run records.
@OrmModel(table: 'stem_workflow_runs')
class StemWorkflowRun extends Model<StemWorkflowRun> {
  /// Creates a workflow run record.
  StemWorkflowRun({
    required this.id,
    required this.namespace,
    required this.workflow,
    required this.status,
    required this.params,
    required this.createdAt,
    required this.updatedAt,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.ownerId,
    this.leaseExpiresAt,
    this.cancellationPolicy,
    this.cancellationData,
  });

  /// Run identifier.
  @OrmField(columnName: 'id', isPrimaryKey: true)
  final String id;

  /// Namespace that owns the workflow run.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Workflow name.
  @OrmField(columnName: 'workflow')
  final String workflow;

  /// Workflow status name.
  @OrmField(columnName: 'status')
  final String status;

  /// Serialized workflow parameters.
  @OrmField(columnName: 'params')
  final String params;

  /// Serialized workflow result payload.
  @OrmField(columnName: 'result')
  final String? result;

  /// Topic the workflow is waiting on, if suspended.
  @OrmField(columnName: 'wait_topic')
  final String? waitTopic;

  /// Timestamp when the workflow should resume.
  @OrmField(columnName: 'resume_at')
  final DateTime? resumeAt;

  /// Last error message recorded.
  @OrmField(columnName: 'last_error')
  final String? lastError;

  /// Serialized suspension data.
  @OrmField(columnName: 'suspension_data')
  final String? suspensionData;

  /// Identifier of the worker/runtime holding the lease, if any.
  @OrmField(columnName: 'owner_id')
  final String? ownerId;

  /// Timestamp when the current lease expires.
  @OrmField(columnName: 'lease_expires_at')
  final DateTime? leaseExpiresAt;

  /// Cancellation policy name.
  @OrmField(columnName: 'cancellation_policy')
  final String? cancellationPolicy;

  /// Serialized cancellation payload.
  @OrmField(columnName: 'cancellation_data')
  final String? cancellationData;

  /// Timestamp when the run was created.
  @OrmField(columnName: 'created_at')
  final DateTime createdAt;

  /// Timestamp when the run was last updated.
  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;
}
