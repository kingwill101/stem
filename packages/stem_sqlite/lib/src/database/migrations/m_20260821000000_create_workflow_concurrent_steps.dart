import 'package:ormed/migrations.dart';

/// Creates durable per-invocation state for concurrent workflow steps.
class CreateWorkflowConcurrentSteps extends Migration {
  const CreateWorkflowConcurrentSteps();

  @override
  void up(SchemaBuilder schema) {
    schema.create('wf_concurrent_steps', (table) {
      table
        ..text('namespace')
        ..text('run_id')
        ..text('invocation_id')
        ..text('branch')
        ..text('step_name')
        ..integer('step_index')
        ..integer('iteration')
        ..integer('revision')
        ..text('status')
        ..text('execution_id')
        ..text('value').nullable()
        ..text('suspension_data').nullable()
        ..text('error').nullable()
        ..text('stack').nullable()
        ..text('updated_at')
        ..primary([
          'namespace',
          'run_id',
          'invocation_id',
        ], name: 'wf_concurrent_steps_primary')
        ..index([
          'namespace',
          'status',
        ], name: 'wf_concurrent_steps_status_idx');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('wf_concurrent_steps', ifExists: true);
  }
}
