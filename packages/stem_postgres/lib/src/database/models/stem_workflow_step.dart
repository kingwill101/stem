import 'package:ormed/ormed.dart';

part 'stem_workflow_step.orm.dart';

@OrmModel(table: 'stem_workflow_steps', primaryKey: ['runId', 'name'])
class StemWorkflowStep extends Model<StemWorkflowStep> {
  StemWorkflowStep({required this.runId, required this.name, this.value});

  @OrmField(columnName: 'run_id')
  final String runId;

  @OrmField(columnName: 'name')
  final String name;

  @OrmField(columnName: 'value')
  final String? value;
}
