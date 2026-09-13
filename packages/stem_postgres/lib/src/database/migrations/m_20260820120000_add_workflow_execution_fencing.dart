import 'package:ormed/migrations.dart';

/// Adds the execution token used to fence stale workflow attempts.
class AddWorkflowExecutionFencing extends Migration {
  /// Creates the migration.
  const AddWorkflowExecutionFencing();

  @override
  void up(SchemaBuilder schema) {
    schema.table('stem_workflow_runs', (table) {
      table.text('execution_id').nullable();
      table.index(['execution_id'], name: 'stem_workflow_runs_execution_idx');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.table('stem_workflow_runs', (table) {
      table
        ..dropIndex('stem_workflow_runs_execution_idx')
        ..dropColumn('execution_id');
    });
  }
}
