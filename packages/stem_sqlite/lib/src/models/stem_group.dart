import 'package:ormed/ormed.dart';

import 'stem_group_result.dart';

part 'stem_group.orm.dart';

@OrmModel(table: 'stem_groups')
class StemGroup extends Model<StemGroup> with TimestampsTZ {
  const StemGroup({
    required this.id,
    required this.expected,
    required this.meta,
    required this.expiresAt,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  final int expected;
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;

  @OrmRelation.hasMany(target: StemGroupResult, foreignKey: 'group_id')
  @OrmField(ignore: true)
  final List<StemGroupResult> results = const [];
}
