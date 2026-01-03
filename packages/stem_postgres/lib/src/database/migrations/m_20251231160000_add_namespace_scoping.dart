import 'package:ormed/migrations.dart';

/// Adds namespace scoping columns to Stem tables.
class AddNamespaceScoping extends Migration {
  /// Creates the migration.
  const AddNamespaceScoping();

  @override
  void up(SchemaBuilder schema) {
    schema
      ..table('stem_broadcast_messages', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(
          ['namespace'],
          name: 'stem_broadcast_messages_namespace_idx',
        );
      })
      ..table('stem_broadcast_ack', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_broadcast_ack_namespace_idx');
      })
      ..table('stem_queue_jobs', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_queue_jobs_namespace_idx');
      })
      ..table('stem_dead_letters', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_dead_letters_namespace_idx');
      })
      ..table('stem_task_results', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_task_results_namespace_idx');
      })
      ..table('stem_groups', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_groups_namespace_idx');
      })
      ..table('stem_group_results', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_group_results_namespace_idx');
      })
      ..table('stem_worker_heartbeats', (table) {
        table.index(
          ['namespace'],
          name: 'stem_worker_heartbeats_namespace_idx',
        );
      })
      ..table('stem_locks', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_locks_namespace_idx');
      })
      ..table('stem_workflow_runs', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_workflow_runs_namespace_idx');
      })
      ..table('stem_workflow_steps', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_workflow_steps_namespace_idx');
      })
      ..table('stem_workflow_watchers', (table) {
        table.text('namespace').defaultValue('stem');
        table.index([
          'namespace',
        ], name: 'stem_workflow_watchers_namespace_idx');
      })
      ..table('stem_schedules', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'stem_schedules_namespace_idx');
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..table('stem_broadcast_messages', (table) {
        table.dropIndex('stem_broadcast_messages_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_broadcast_ack', (table) {
        table.dropIndex('stem_broadcast_ack_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_queue_jobs', (table) {
        table.dropIndex('stem_queue_jobs_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_dead_letters', (table) {
        table.dropIndex('stem_dead_letters_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_task_results', (table) {
        table.dropIndex('stem_task_results_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_groups', (table) {
        table.dropIndex('stem_groups_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_group_results', (table) {
        table.dropIndex('stem_group_results_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_worker_heartbeats', (table) {
        table.dropIndex('stem_worker_heartbeats_namespace_idx');
      })
      ..table('stem_locks', (table) {
        table.dropIndex('stem_locks_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_workflow_runs', (table) {
        table.dropIndex('stem_workflow_runs_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_workflow_steps', (table) {
        table.dropIndex('stem_workflow_steps_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_workflow_watchers', (table) {
        table.dropIndex('stem_workflow_watchers_namespace_idx');
        table.dropColumn('namespace');
      })
      ..table('stem_schedules', (table) {
        table.dropIndex('stem_schedules_namespace_idx');
        table.dropColumn('namespace');
      });
  }
}
