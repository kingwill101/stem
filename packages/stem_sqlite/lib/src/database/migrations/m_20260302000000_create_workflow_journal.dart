import 'package:ormed/migrations.dart';

/// Creates the independent workflow journal table.
class CreateWorkflowJournal extends Migration {
  /// Creates the migration.
  const CreateWorkflowJournal();

  @override
  void up(SchemaBuilder schema) {
    schema.create('wf_journal', (table) {
      table
        ..text('namespace')
        ..text('run_id')
        ..text('kind')
        ..text('name')
        ..integer('revision')
        ..text('data')
        ..integer('position').nullable()
        ..primary(
          ['namespace', 'run_id', 'kind', 'name'],
          name: 'wf_journal_primary',
        )
        ..index(
          ['namespace', 'run_id', 'kind', 'position'],
          name: 'wf_journal_compensation_order_idx',
        );
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('wf_journal', ifExists: true);
  }
}
