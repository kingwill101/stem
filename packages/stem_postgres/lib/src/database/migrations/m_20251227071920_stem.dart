import 'package:ormed/migrations.dart';

class Stem extends Migration {
  const Stem();

  @override
  void up(SchemaBuilder schema) {
    schema.create('stem_broadcast_messages', (table) {
      table.text('id').primaryKey();
      table.text('channel');
      table.json('envelope');
      table.text('delivery').defaultValue('at-least-once');
      table.timestampsTz();
      table.index([
        'channel',
        'created_at',
      ], name: 'stem_broadcast_messages_channel_created_idx');
    });

    schema.create('stem_broadcast_ack', (table) {
      table.text('message_id');
      table.text('worker_id');
      table.timestampTz('acknowledged_at').nullable();
      table.timestampsTz();
      table.primary([
        'message_id',
        'worker_id',
      ], name: 'stem_broadcast_ack_primary');
      table.foreign(
        ['message_id'],
        references: 'stem_broadcast_messages',
        referencedColumns: ['id'],
        onDelete: ReferenceAction.cascade,
      );
    });

    schema.create('stem_queue_jobs', (table) {
      table.text('id').primaryKey();
      table.text('queue');
      table.json('envelope');
      table.integer('attempt').defaultValue(0);
      table.integer('max_retries').defaultValue(0);
      table.integer('priority').defaultValue(0);
      table.timestampTz('not_before').nullable();
      table.timestampTz('locked_at').nullable();
      table.timestampTz('locked_until').nullable();
      table.text('locked_by').nullable();
      table.timestampsTz();
      table.index([
        'queue',
        'priority',
        'created_at',
      ], name: 'stem_queue_jobs_queue_priority_idx');
      table.index(['not_before'], name: 'stem_queue_jobs_not_before_idx');
    });

    schema.create('stem_dead_letters', (table) {
      table.text('id').primaryKey();
      table.text('queue');
      table.json('envelope');
      table.text('reason').nullable();
      table.json('meta').nullable();
      table.timestampTz('dead_at');
      table.index([
        'queue',
        'dead_at',
      ], name: 'stem_dead_letters_queue_dead_at_idx');
    });

    schema.create('stem_task_results', (table) {
      table.text('id').primaryKey();
      table.text('state');
      table.json('payload').nullable();
      table.json('error').nullable();
      table.integer('attempt').defaultValue(0);
      table.json('meta').defaultValue('{}');
      table.timestampTz('expires_at');
      table.timestampsTz();
      table.index(['expires_at'], name: 'stem_task_results_expires_at_idx');
    });

    schema.create('stem_groups', (table) {
      table.text('id').primaryKey();
      table.integer('expected');
      table.json('meta').defaultValue('{}');
      table.timestampTz('expires_at');
      table.timestampsTz();
      table.index(['expires_at'], name: 'stem_groups_expires_at_idx');
    });

    schema.create('stem_group_results', (table) {
      table.text('group_id');
      table.text('task_id');
      table.text('state');
      table.json('payload').nullable();
      table.json('error').nullable();
      table.integer('attempt').defaultValue(0);
      table.json('meta').defaultValue('{}');
      table.timestampsTz();
      table.primary([
        'group_id',
        'task_id',
      ], name: 'stem_group_results_primary');
      table.index(['group_id'], name: 'stem_group_results_group_idx');
      table.foreign(
        ['group_id'],
        references: 'stem_groups',
        referencedColumns: ['id'],
        onDelete: ReferenceAction.cascade,
      );
    });

    schema.create('stem_worker_heartbeats', (table) {
      table.text('worker_id').primaryKey();
      table.text('namespace');
      table.timestampTz('timestamp');
      table.integer('isolate_count');
      table.integer('inflight');
      table.json('queues').defaultValue('{}');
      table.timestampTz('last_lease_renewal').nullable();
      table.text('version');
      table.json('extras').defaultValue('{}');
      table.timestampTz('expires_at');
      table.timestampTz('deleted_at').nullable();
      table.timestampsTz();
      table.index([
        'expires_at',
      ], name: 'stem_worker_heartbeats_expires_at_idx');
    });

    schema.create('stem_locks', (table) {
      table.text('key').primaryKey();
      table.text('owner');
      table.timestampTz('expires_at');
      table.timestampTz('created_at');
      table.index(['expires_at'], name: 'stem_locks_expires_at_idx');
    });

    schema.create('stem_workflow_runs', (table) {
      table.text('id').primaryKey();
      table.text('workflow');
      table.text('status');
      table.text('params');
      table.text('result').nullable();
      table.text('wait_topic').nullable();
      table.timestampTz('resume_at').nullable();
      table.text('last_error').nullable();
      table.text('suspension_data').nullable();
      table.text('cancellation_policy').nullable();
      table.text('cancellation_data').nullable();
      table.timestampsTz();
      table.index(['resume_at'], name: 'stem_workflow_runs_resume_at_idx');
      table.index(['wait_topic'], name: 'stem_workflow_runs_wait_topic_idx');
    });

    schema.create('stem_workflow_steps', (table) {
      table.text('run_id');
      table.text('name');
      table.text('value').nullable();
      table.primary(['run_id', 'name'], name: 'stem_workflow_steps_primary');
      table.foreign(
        ['run_id'],
        references: 'stem_workflow_runs',
        referencedColumns: ['id'],
        onDelete: ReferenceAction.cascade,
      );
    });

    schema.create('stem_workflow_watchers', (table) {
      table.text('run_id').primaryKey();
      table.text('step_name');
      table.text('topic');
      table.text('data').nullable();
      table.timestampTz('created_at');
      table.timestampTz('deadline').nullable();
      table.foreign(
        ['run_id'],
        references: 'stem_workflow_runs',
        referencedColumns: ['id'],
        onDelete: ReferenceAction.cascade,
      );
      table.index([
        'topic',
        'created_at',
      ], name: 'stem_workflow_watchers_topic_created_idx');
    });

    schema.create('stem_revokes', (table) {
      table.text('task_id').primaryKey();
      table.text('namespace');
      table.boolean('terminate').defaultValue(false);
      table.text('reason').nullable();
      table.text('requested_by').nullable();
      table.timestampTz('issued_at');
      table.timestampTz('expires_at').nullable();
      table.bigInteger('version');
      table.timestampsTz();
      table.index(['namespace'], name: 'stem_revokes_namespace_idx');
      table.index(['expires_at'], name: 'stem_revokes_expires_at_idx');
    });

    schema.create('stem_schedules', (table) {
      table.text('id').primaryKey();
      table.text('task_name');
      table.text('queue');
      table.text('spec');
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
      table.timestampsTz();
      table.index(['task_name'], name: 'stem_schedules_task_name_idx');
      table.index(['queue'], name: 'stem_schedules_queue_idx');
      table.index(['next_run_at'], name: 'stem_schedules_next_run_at_idx');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('stem_schedules', ifExists: true);
    schema.drop('stem_revokes', ifExists: true);
    schema.drop('stem_workflow_watchers', ifExists: true);
    schema.drop('stem_workflow_steps', ifExists: true);
    schema.drop('stem_workflow_runs', ifExists: true);
    schema.drop('stem_locks', ifExists: true);
    schema.drop('stem_broadcast_ack', ifExists: true);
    schema.drop('stem_broadcast_messages', ifExists: true);
    schema.drop('stem_worker_heartbeats', ifExists: true);
    schema.drop('stem_group_results', ifExists: true);
    schema.drop('stem_groups', ifExists: true);
    schema.drop('stem_task_results', ifExists: true);
    schema.drop('stem_dead_letters', ifExists: true);
    schema.drop('stem_queue_jobs', ifExists: true);
  }
}
