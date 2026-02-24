import 'package:ormed/migrations.dart';

/// Adds a revoke store table for worker control state.
class AddRevokeStore extends Migration {
  /// Creates the migration.
  const AddRevokeStore();

  @override
  void up(SchemaBuilder schema) {
    schema.create('stem_revokes', (table) {
      table
        ..text('namespace')
        ..text('task_id')
        ..integer('version')
        ..timestamp('issued_at');
      table.integer('terminate').defaultValue(0);
      table.text('reason').nullable();
      table.text('requested_by').nullable();
      table.timestamp('expires_at').nullable();
      table
        ..timestampsTz()
        ..primary([
          'namespace',
          'task_id',
        ], name: 'stem_revokes_primary')
        ..index(['namespace'], name: 'stem_revokes_namespace_idx')
        ..index(['expires_at'], name: 'stem_revokes_expires_at_idx');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('stem_revokes', ifExists: true);
  }
}
