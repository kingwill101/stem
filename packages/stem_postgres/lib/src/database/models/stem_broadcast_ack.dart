import 'package:ormed/ormed.dart';

part 'stem_broadcast_ack.orm.dart';

/// Database model for broadcast message acknowledgements.
@OrmModel(table: 'stem_broadcast_ack')
class StemBroadcastAck extends Model<StemBroadcastAck> with TimestampsTZ {
  /// Creates a broadcast acknowledgement record.
  const StemBroadcastAck({
    required this.messageId,
    required this.workerId,
    required this.namespace,
    this.acknowledgedAt,
  });

  /// Broadcast message identifier.
  @OrmField(isPrimaryKey: true, columnName: 'message_id')
  final String messageId;

  /// Worker identifier that acknowledged the message.
  @OrmField(isPrimaryKey: true, columnName: 'worker_id')
  final String workerId;

  /// Namespace that owns the acknowledgement.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Timestamp when the acknowledgement was recorded.
  @OrmField(columnName: 'acknowledged_at')
  final DateTime? acknowledgedAt;
}
