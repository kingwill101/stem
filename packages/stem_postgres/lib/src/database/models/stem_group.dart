import 'package:ormed/ormed.dart';

part 'stem_group.orm.dart';

/// Database model for task group metadata.
@OrmModel(table: 'stem_groups')
class StemGroup extends Model<StemGroup> with TimestampsTZ {
  /// Creates a task group record.
  const StemGroup({
    required this.id,
    required this.expected,
    required this.meta,
    required this.expiresAt,
  });

  /// Group identifier.
  @OrmField(isPrimaryKey: true)
  final String id;

  /// Expected number of tasks in the group.
  final int expected;

  /// Group metadata stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  /// Timestamp when the group expires.
  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;
}
