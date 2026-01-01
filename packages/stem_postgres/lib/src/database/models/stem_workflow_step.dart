import 'package:ormed/ormed.dart';

part 'stem_workflow_step.orm.dart';

/// Database model for workflow step checkpoints.
@OrmModel(table: 'stem_workflow_steps', primaryKey: ['runId', 'name'])
class StemWorkflowStep extends Model<StemWorkflowStep> {
  /// Creates a workflow step checkpoint record.
  StemWorkflowStep({
    required this.runId,
    required this.name,
    required this.namespace,
    this.value,
  });

  /// Workflow run identifier.
  @OrmField(columnName: 'run_id')
  final String runId;

  /// Step name.
  @OrmField(columnName: 'name')
  final String name;

  /// Namespace that owns the workflow step.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Serialized step value.
  @OrmField(columnName: 'value')
  final String? value;
}
