import 'package:ormed/ormed.dart';

import 'package:stem_sqlite/src/models/stem_group_result.dart';

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
    this.results = const [],
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

  /// Results associated with the group when eagerly loaded.
  @OrmRelation.hasMany(target: StemGroupResult, foreignKey: 'group_id')
  @OrmField(ignore: true)
  final List<StemGroupResult> results;
}
