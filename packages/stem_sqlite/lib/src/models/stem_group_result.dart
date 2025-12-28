import 'package:ormed/ormed.dart';

import 'stem_group.dart';

part 'stem_group_result.orm.dart';

@OrmModel(table: 'stem_group_results', primaryKey: ['groupId', 'taskId'])
class StemGroupResult  extends Model<StemGroupResult> with TimestampsTZ {
   const StemGroupResult({
    required this.groupId,
    required this.taskId,
    required this.state,
    this.payload,
    this.error,
    required this.attempt,
    required this.meta,
  });

  @OrmField(columnName: 'group_id')
  final String groupId;

  @OrmField(columnName: 'task_id')
  final String taskId;

  final String state;
  @OrmField(cast: 'json')
  final Object? payload;
  @OrmField(cast: 'json')
  final Object? error;
  final int attempt;
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  @OrmRelation.belongsTo(target: StemGroup, foreignKey: 'group_id')
  @OrmField(ignore: true)
  final StemGroup? group = null;
}
