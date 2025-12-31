import 'package:ormed/ormed.dart';

part 'stem_broadcast_message.orm.dart';

/// Database model for broadcast messages.
@OrmModel(table: 'stem_broadcast_messages')
class StemBroadcastMessage extends Model<StemBroadcastMessage>
    with TimestampsTZ {
  /// Creates a broadcast message record.
  const StemBroadcastMessage({
    required this.id,
    required this.channel,
    required this.envelope,
    required this.delivery,
  });

  /// Broadcast message identifier.
  @OrmField(isPrimaryKey: true)
  final String id;

  /// Broadcast channel name.
  final String channel;

  /// Envelope payload stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;

  /// Delivery mode for the broadcast message.
  final String delivery;
}
