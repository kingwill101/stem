import 'package:ormed/ormed.dart';

part 'stem_broadcast_message.orm.dart';

@OrmModel(table: 'stem_broadcast_messages')
class StemBroadcastMessage extends Model<StemBroadcastMessage>
    with TimestampsTZ {
  const StemBroadcastMessage({
    required this.id,
    required this.channel,
    required this.envelope,
    required this.delivery,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  final String channel;

  @OrmField(cast: 'json')
  final Map<String, Object?> envelope;

  final String delivery;
}
