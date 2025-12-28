import 'package:ormed/ormed.dart';

part 'stem_task_result.orm.dart';

@OrmModel(table: 'stem_task_results')
class StemTaskResult extends Model<StemTaskResult> with Timestamps {
  const StemTaskResult({
    required this.id,
    required this.state,
    this.payload,
    this.error,
    required this.attempt,
    required this.meta,
    required this.expiresAt,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  final String state;
  @OrmField(cast: 'json')
  final Object? payload;
  @OrmField(cast: 'json')
  final Object? error;
  final int attempt;
  @OrmField(cast: 'json')
  final Map<String, Object?> meta;

  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;
}
