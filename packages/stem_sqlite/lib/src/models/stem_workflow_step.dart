import 'package:ormed/ormed.dart';

part 'stem_workflow_step.orm.dart';

/// Database model for workflow step checkpoints.
@OrmModel(table: 'wf_steps', primaryKey: ['runId', 'name'])
class StemWorkflowStep extends Model<StemWorkflowStep> {
  /// Creates a workflow step checkpoint record.
  StemWorkflowStep({required this.runId, required this.name, this.value});

  /// Workflow run identifier.
  @OrmField(columnName: 'run_id')
  final String runId;

  /// Step name.
  @OrmField(columnName: 'name')
  final String name;

  /// Serialized step value.
  @OrmField(columnName: 'value')
  final String? value;
}
