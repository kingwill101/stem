import 'package:ormed/migrations.dart';

/// Adds the durable PostgreSQL task publication outbox.
class AddTaskOutbox extends Migration {
  /// Creates the migration.
  const AddTaskOutbox();

  @override
  void up(SchemaBuilder schema) {
    schema.create('stem_task_outbox', (table) {
      table
        ..text('id').primaryKey()
        ..text('namespace')
        ..json('envelope')
        ..json('routing').nullable()
        ..text('status').defaultValue('pending')
        ..timestampTz('available_at')
        ..integer('attempts').defaultValue(0)
        ..timestampTz('locked_at').nullable()
        ..timestampTz('locked_until').nullable()
        ..text('locked_by').nullable()
        ..text('last_error').nullable()
        ..timestampTz('dispatched_at').nullable()
        ..timestampsTz()
        ..index(
          ['namespace', 'status', 'available_at'],
          name: 'stem_task_outbox_claim_idx',
        )
        ..index(
          ['locked_until'],
          name: 'stem_task_outbox_locked_idx',
        );
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('stem_task_outbox', ifExists: true);
  }
}
