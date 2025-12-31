import 'package:ormed/migrations.dart';

/// Creates workflow tables for SQLite.
class CreateWorkflowTables extends Migration {
  /// Creates the migration.
  const CreateWorkflowTables();

  @override
  void up(SchemaBuilder schema) {
    schema
      ..create('wf_runs', (table) {
        table.text('id').primaryKey();
        table
          ..text('workflow')
          ..text('status')
          ..text('params');
        table.text('result').nullable();
        table.text('wait_topic').nullable();
        table.timestamp('resume_at').nullable();
        table.text('last_error').nullable();
        table.text('suspension_data').nullable();
        table.text('cancellation_policy').nullable();
        table.text('cancellation_data').nullable();
        table
          ..timestampsTz()
          ..index(['resume_at'], name: 'wf_runs_resume_idx')
          ..index(['wait_topic'], name: 'wf_runs_topic_idx');
      })
      ..create('wf_steps', (table) {
        table
          ..text('run_id')
          ..text('name');
        table.text('value').nullable();
        table
          ..primary(['run_id', 'name'], name: 'wf_steps_primary')
          ..foreign(
            ['run_id'],
            references: 'wf_runs',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          );
      })
      ..create('wf_watchers', (table) {
        table.text('run_id').primaryKey();
        table
          ..text('step_name')
          ..text('topic');
        table.text('data').nullable();
        table.timestamp('created_at');
        table.timestamp('deadline').nullable();
        table
          ..foreign(
            ['run_id'],
            references: 'wf_runs',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          )
          ..index(['topic', 'created_at'], name: 'wf_watchers_topic_idx');
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..drop('wf_watchers', ifExists: true)
      ..drop('wf_steps', ifExists: true)
      ..drop('wf_runs', ifExists: true);
  }
}
