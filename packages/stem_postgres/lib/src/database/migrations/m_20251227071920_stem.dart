import 'package:ormed/migrations.dart';

/// Initial Stem schema migration for PostgreSQL.
class Stem extends Migration {
  /// Creates the migration.
  const Stem();

  @override
  void up(SchemaBuilder schema) {
    schema
      ..create('stem_broadcast_messages', (table) {
        table.text('id').primaryKey();
        table
          ..text('channel')
          ..json('envelope');
        table.text('delivery').defaultValue('at-least-once');
        table
          ..timestampsTz()
          ..index([
            'channel',
            'created_at',
          ], name: 'stem_broadcast_messages_channel_created_idx');
      })
      ..create('stem_broadcast_ack', (table) {
        table
          ..text('message_id')
          ..text('worker_id');
        table.timestampTz('acknowledged_at').nullable();
        table
          ..timestampsTz()
          ..primary([
            'message_id',
            'worker_id',
          ], name: 'stem_broadcast_ack_primary')
          ..foreign(
            ['message_id'],
            references: 'stem_broadcast_messages',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          );
      })
      ..create('stem_queue_jobs', (table) {
        table.text('id').primaryKey();
        table
          ..text('queue')
          ..json('envelope');
        table.integer('attempt').defaultValue(0);
        table.integer('max_retries').defaultValue(0);
        table.integer('priority').defaultValue(0);
        table.timestampTz('not_before').nullable();
        table.timestampTz('locked_at').nullable();
        table.timestampTz('locked_until').nullable();
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
          ..timestampTz('dead_at')
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
          ..timestampTz('expires_at')
          ..timestampsTz()
          ..index(['expires_at'], name: 'stem_task_results_expires_at_idx');
      })
      ..create('stem_groups', (table) {
        table.text('id').primaryKey();
        table.integer('expected');
        table.json('meta').defaultValue('{}');
        table
          ..timestampTz('expires_at')
          ..timestampsTz()
          ..index(['expires_at'], name: 'stem_groups_expires_at_idx');
      })
      ..create('stem_group_results', (table) {
        table
          ..text('group_id')
          ..text('task_id')
          ..text('state');
        table.json('payload').nullable();
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
          ..timestampTz('timestamp')
          ..integer('isolate_count')
          ..integer('inflight')
          ..json('queues').defaultValue('{}')
          ..timestampTz('last_lease_renewal').nullable()
          ..text('version')
          ..json('extras').defaultValue('{}')
          ..timestampTz('expires_at')
          ..timestampTz('deleted_at').nullable()
          ..timestampsTz()
          ..index([
            'expires_at',
          ], name: 'stem_worker_heartbeats_expires_at_idx');
      })
      ..create('stem_locks', (table) {
        table.text('key').primaryKey();
        table
          ..text('owner')
          ..timestampTz('expires_at')
          ..timestampTz('created_at')
          ..index(['expires_at'], name: 'stem_locks_expires_at_idx');
      })
      ..create('stem_workflow_runs', (table) {
        table.text('id').primaryKey();
        table
          ..text('workflow')
          ..text('status')
          ..text('params');
        table.text('result').nullable();
        table.text('wait_topic').nullable();
        table.timestampTz('resume_at').nullable();
        table.text('last_error').nullable();
        table.text('suspension_data').nullable();
        table.text('cancellation_policy').nullable();
        table.text('cancellation_data').nullable();
        table
          ..timestampsTz()
          ..index(['resume_at'], name: 'stem_workflow_runs_resume_at_idx')
          ..index(['wait_topic'], name: 'stem_workflow_runs_wait_topic_idx');
      })
      ..create('stem_workflow_steps', (table) {
        table
          ..text('run_id')
          ..text('name');
        table.text('value').nullable();
        table
          ..primary(['run_id', 'name'], name: 'stem_workflow_steps_primary')
          ..foreign(
            ['run_id'],
            references: 'stem_workflow_runs',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          );
      })
      ..create('stem_workflow_watchers', (table) {
        table.text('run_id').primaryKey();
        table
          ..text('step_name')
          ..text('topic');
        table.text('data').nullable();
        table.timestampTz('created_at');
        table.timestampTz('deadline').nullable();
        table
          ..foreign(
            ['run_id'],
            references: 'stem_workflow_runs',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          )
          ..index([
            'topic',
            'created_at',
          ], name: 'stem_workflow_watchers_topic_created_idx');
      })
      ..create('stem_revokes', (table) {
        table.text('task_id').primaryKey();
        table.text('namespace');
        table.boolean('terminate').defaultValue(false);
        table.text('reason').nullable();
        table.text('requested_by').nullable();
        table.timestampTz('issued_at');
        table.timestampTz('expires_at').nullable();
        table
          ..bigInteger('version')
          ..timestampsTz()
          ..index(['namespace'], name: 'stem_revokes_namespace_idx')
          ..index(['expires_at'], name: 'stem_revokes_expires_at_idx');
      })
      ..create('stem_schedules', (table) {
        table.text('id').primaryKey();
        table
          ..text('task_name')
          ..text('queue')
          ..text('spec');
        table.text('args').nullable();
        table.text('kwargs').nullable();
        table.boolean('enabled').defaultValue(true);
        table.integer('jitter').nullable();
        table.timestampTz('last_run_at').nullable();
        table.timestampTz('next_run_at').nullable();
        table.integer('last_jitter').nullable();
        table.text('last_error').nullable();
        table.text('timezone').nullable();
        table.integer('total_run_count').defaultValue(0);
        table.timestampTz('last_success_at').nullable();
        table.timestampTz('last_error_at').nullable();
        table.integer('drift').nullable();
        table.timestampTz('expire_at').nullable();
        table.text('meta').nullable();
        table.integer('version').defaultValue(0);
        table
          ..timestampsTz()
          ..index(['task_name'], name: 'stem_schedules_task_name_idx')
          ..index(['queue'], name: 'stem_schedules_queue_idx')
          ..index(['next_run_at'], name: 'stem_schedules_next_run_at_idx');
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..drop('stem_schedules', ifExists: true)
      ..drop('stem_revokes', ifExists: true)
      ..drop('stem_workflow_watchers', ifExists: true)
      ..drop('stem_workflow_steps', ifExists: true)
      ..drop('stem_workflow_runs', ifExists: true)
      ..drop('stem_locks', ifExists: true)
      ..drop('stem_broadcast_ack', ifExists: true)
      ..drop('stem_broadcast_messages', ifExists: true)
      ..drop('stem_worker_heartbeats', ifExists: true)
      ..drop('stem_group_results', ifExists: true)
      ..drop('stem_groups', ifExists: true)
      ..drop('stem_task_results', ifExists: true)
      ..drop('stem_dead_letters', ifExists: true)
      ..drop('stem_queue_jobs', ifExists: true);
  }
}
