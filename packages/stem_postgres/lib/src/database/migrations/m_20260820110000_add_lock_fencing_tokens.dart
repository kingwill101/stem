import 'package:ormed/migrations.dart';

/// Adds durable fencing tokens to distributed lock records.
class AddLockFencingTokens extends Migration {
  /// Creates the migration.
  const AddLockFencingTokens();

  @override
  void up(SchemaBuilder schema) {
    schema.table('stem_locks', (table) {
      table.bigInteger('fencing_token').defaultValue(0);
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.table('stem_locks', (table) {
      table.dropColumn('fencing_token');
    });
  }
}
