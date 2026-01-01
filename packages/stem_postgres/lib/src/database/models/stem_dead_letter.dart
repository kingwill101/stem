import 'package:ormed/ormed.dart';

part 'stem_dead_letter.orm.dart';

/// Database model for dead letter entries.
@OrmModel(table: 'stem_dead_letters')
class StemDeadLetter extends Model<StemDeadLetter> {
  /// Creates a dead letter record.
  const StemDeadLetter({
    required this.id,
    required this.namespace,
    required this.queue,
    required this.envelope,
    required this.deadAt,
    this.reason,
    this.meta,
  });

  /// Dead letter identifier.
  @OrmField(isPrimaryKey: true)
  final String id;

  /// Namespace that owns the dead letter entry.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Queue name associated with the dead letter.
  final String queue;

  /// Envelope payload stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;

  /// Optional failure reason.
  final String? reason;

  /// Optional metadata stored alongside the entry.
  @OrmField(cast: 'json')
  final Map<String, Object?>? meta;

  /// Timestamp when the job was dead-lettered.
  @OrmField(columnName: 'dead_at')
  final DateTime deadAt;
}
