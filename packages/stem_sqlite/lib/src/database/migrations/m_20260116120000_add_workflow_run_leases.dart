import 'package:ormed/migrations.dart';

/// Adds workflow run lease tracking fields.
class AddWorkflowRunLeases extends Migration {
  /// Creates the migration.
  const AddWorkflowRunLeases();

  @override
  void up(SchemaBuilder schema) {
    schema.table('wf_runs', (table) {
      table.text('owner_id').nullable();
      table.timestamp('lease_expires_at').nullable();
      table..index(['owner_id'], name: 'wf_runs_owner_idx')
      ..index(['lease_expires_at'], name: 'wf_runs_lease_idx');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.table('wf_runs', (table) {
      table
        ..dropIndex('wf_runs_owner_idx')
        ..dropIndex('wf_runs_lease_idx')
        ..dropColumn('owner_id')
        ..dropColumn('lease_expires_at');
    });
  }
}
