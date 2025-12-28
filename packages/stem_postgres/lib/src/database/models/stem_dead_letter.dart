import 'package:ormed/ormed.dart';

part 'stem_dead_letter.orm.dart';

@OrmModel(table: 'stem_dead_letters')
class StemDeadLetter extends Model<StemDeadLetter> {
  const StemDeadLetter({
    required this.id,
    required this.queue,
    required this.envelope,
    this.reason,
    this.meta,
    required this.deadAt,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  final String queue;

  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;

  final String? reason;

  @OrmField(cast: 'json')
  final Map<String, Object?>? meta;

  @OrmField(columnName: 'dead_at')
  final DateTime deadAt;
}
