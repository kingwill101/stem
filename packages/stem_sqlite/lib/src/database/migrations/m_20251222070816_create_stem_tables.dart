import 'package:ormed/migrations.dart';

/// Creates the initial Stem tables in SQLite.
class CreateStemTables extends Migration {
  /// Creates the migration.
  const CreateStemTables();

  @override
  void up(SchemaBuilder schema) {
    schema
      ..create('stem_queue_jobs', (table) {
        table.text('id').primaryKey();
        table
          ..text('queue')
          ..json('envelope');
        table.integer('attempt').defaultValue(0);
        table.integer('max_retries').defaultValue(0);
        table.integer('priority').defaultValue(0);
        table.timestamp('not_before').nullable();
        table.timestamp('locked_at').nullable();
        table.timestamp('locked_until').nullable();
        table.text('locked_by').nullable();
        table
          ..timestampsTz()
          ..index([
            'queue',
            'priority',
            'created_at',
          ], name: 'stem_queue_jobs_queue_priority_idx')
          ..index(['not_before'], name: 'stem_queue_jobs_not_before_idx');
      })
      ..create('stem_dead_letters', (table) {
        table.text('id').primaryKey();
        table
          ..text('queue')
          ..json('envelope');
        table.text('reason').nullable();
        table.json('meta').nullable();
        table
          ..timestamp('dead_at')
          ..index([
            'queue',
            'dead_at',
          ], name: 'stem_dead_letters_queue_dead_at_idx');
      })
      ..create('stem_task_results', (table) {
        table.text('id').primaryKey();
        table.text('state');
        table.json('payload').nullable();
        table.json('error').nullable();
        table.integer('attempt').defaultValue(0);
        table.json('meta').defaultValue('{}');
        table
          ..timestamp('expires_at')
          ..timestampsTz()
          ..index(['expires_at'], name: 'stem_task_results_expires_at_idx');
      })
      ..create('stem_groups', (table) {
        table.text('id').primaryKey();
        table.integer('expected');
        table.json('meta').defaultValue('{}');
        table
          ..timestamp('expires_at')
          ..timestampsTz()
          ..index(['expires_at'], name: 'stem_groups_expires_at_idx');
      })
      ..create('stem_group_results', (table) {
        table
          ..text('group_id')
          ..text('task_id')
          ..text('state')
          ..json('payload').nullable();
        table.json('error').nullable();
        table.integer('attempt').defaultValue(0);
        table.json('meta').defaultValue('{}');
        table
          ..timestampsTz()
          ..primary([
            'group_id',
            'task_id',
          ], name: 'stem_group_results_primary')
          ..index(['group_id'], name: 'stem_group_results_group_idx')
          ..foreign(
            ['group_id'],
            references: 'stem_groups',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          );
      })
      ..create('stem_worker_heartbeats', (table) {
        table.text('worker_id').primaryKey();
        table
          ..text('namespace')
          ..timestamp('timestamp')
          ..integer('isolate_count')
          ..integer('inflight')
          ..json('queues').defaultValue('{}');
        table.timestamp('last_lease_renewal').nullable();
        table.text('version');
        table.json('extras').defaultValue('{}');
        table.timestamp('expires_at');
        table.timestamp('deleted_at').nullable();
        table
          ..timestampsTz()
          ..index([
            'expires_at',
          ], name: 'stem_worker_heartbeats_expires_at_idx');
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..drop('stem_worker_heartbeats', ifExists: true)
      ..drop('stem_group_results', ifExists: true)
      ..drop('stem_groups', ifExists: true)
      ..drop('stem_task_results', ifExists: true)
      ..drop('stem_dead_letters', ifExists: true)
      ..drop('stem_queue_jobs', ifExists: true);
  }
}
