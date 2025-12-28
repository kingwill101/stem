import 'package:ormed/ormed.dart';

part 'stem_broadcast_ack.orm.dart';

@OrmModel(table: 'stem_broadcast_ack')
class StemBroadcastAck extends Model<StemBroadcastAck> with TimestampsTZ {
  const StemBroadcastAck({
    required this.messageId,
    required this.workerId,
    this.acknowledgedAt,
  });

  @OrmField(isPrimaryKey: true, columnName: 'message_id')
  final String messageId;

  @OrmField(isPrimaryKey: true, columnName: 'worker_id')
  final String workerId;

  @OrmField(columnName: 'acknowledged_at')
  final DateTime? acknowledgedAt;
}
