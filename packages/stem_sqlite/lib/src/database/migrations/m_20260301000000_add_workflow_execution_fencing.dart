import 'package:ormed/migrations.dart';

/// Adds the fencing token for workflow execution attempts.
class AddWorkflowExecutionFencing extends Migration {
  /// Creates the migration.
  const AddWorkflowExecutionFencing();

  @override
  void up(SchemaBuilder schema) {
    schema.table('wf_runs', (table) {
      table.text('execution_id').nullable();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.table('wf_runs', (table) {
      table.dropColumn('execution_id');
    });
  }
}
