import 'package:ormed/migrations.dart';

/// Adds namespace scoping columns to SQLite tables.
class AddNamespaceScoping extends Migration {
  /// Creates the migration.
  const AddNamespaceScoping();

  @override
  void up(SchemaBuilder schema) {
    schema
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
      ..table('wf_runs', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'wf_runs_namespace_idx');
      })
      ..table('wf_steps', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'wf_steps_namespace_idx');
      })
      ..table('wf_watchers', (table) {
        table.text('namespace').defaultValue('stem');
        table.index(['namespace'], name: 'wf_watchers_namespace_idx');
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..table('stem_queue_jobs', (table) {
        table
          ..dropIndex('stem_queue_jobs_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('stem_dead_letters', (table) {
        table
          ..dropIndex('stem_dead_letters_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('stem_task_results', (table) {
        table
          ..dropIndex('stem_task_results_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('stem_groups', (table) {
        table
          ..dropIndex('stem_groups_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('stem_group_results', (table) {
        table
          ..dropIndex('stem_group_results_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('stem_worker_heartbeats', (table) {
        table.dropIndex('stem_worker_heartbeats_namespace_idx');
      })
      ..table('wf_runs', (table) {
        table
          ..dropIndex('wf_runs_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('wf_steps', (table) {
        table
          ..dropIndex('wf_steps_namespace_idx')
          ..dropColumn('namespace');
      })
      ..table('wf_watchers', (table) {
        table
          ..dropIndex('wf_watchers_namespace_idx')
          ..dropColumn('namespace');
      });
  }
}
