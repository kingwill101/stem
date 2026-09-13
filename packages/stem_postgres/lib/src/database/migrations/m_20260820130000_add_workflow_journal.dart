import 'package:ormed/migrations.dart';

/// Adds the versioned workflow journal, separate from ordinary checkpoints.
class AddWorkflowJournal extends Migration {
  /// Creates the migration.
  const AddWorkflowJournal();

  @override
  void up(SchemaBuilder schema) {
    schema.create('stem_workflow_journal', (table) {
      table
        ..text('namespace')
        ..text('run_id')
        ..text('kind')
        ..text('name')
        ..integer('revision')
        ..integer('position').nullable()
        ..json('data')
        ..primary(
          ['namespace', 'run_id', 'kind', 'name'],
          name: 'stem_workflow_journal_primary',
        )
        ..index(
          ['namespace', 'run_id', 'kind', 'position'],
          name: 'stem_workflow_journal_compensation_position_idx',
        );
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('stem_workflow_journal');
  }
}
