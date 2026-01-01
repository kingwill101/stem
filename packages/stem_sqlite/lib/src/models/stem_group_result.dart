import 'package:ormed/ormed.dart';

import 'package:stem_sqlite/src/models/stem_group.dart';

part 'stem_group_result.orm.dart';

/// Database model for task results associated with a group.
@OrmModel(table: 'stem_group_results', primaryKey: ['groupId', 'taskId'])
class StemGroupResult extends Model<StemGroupResult> with TimestampsTZ {
  /// Creates a task group result record.
  const StemGroupResult({
    required this.groupId,
    required this.taskId,
    required this.namespace,
    required this.state,
    required this.attempt,
    required this.meta,
    this.payload,
    this.error,
    this.group,
  });

  /// Group identifier for the result.
  @OrmField(columnName: 'group_id')
  final String groupId;

  /// Task identifier for the result.
  @OrmField(columnName: 'task_id')
  final String taskId;

  /// Namespace that owns the group result.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Task state name.
  final String state;

  /// Task payload stored as JSON.
  @OrmField(cast: 'json')
  final Object? payload;

  /// Task error stored as JSON.
  @OrmField(cast: 'json')
  final Object? error;

  /// Task attempt count.
  final int attempt;

  /// Result metadata stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  /// Related group record, when eagerly loaded.
  @OrmRelation.belongsTo(target: StemGroup, foreignKey: 'group_id')
  @OrmField(ignore: true)
  final StemGroup? group;
}
