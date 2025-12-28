import 'package:ormed/ormed.dart';

part 'stem_lock.orm.dart';

@OrmModel(table: 'stem_locks')
class StemLock extends Model<StemLock> {
  StemLock({
    required this.key,
    required this.owner,
    required this.expiresAt,
    required this.createdAt,
  });

  @OrmField(columnName: 'key', isPrimaryKey: true)
  final String key;

  @OrmField(columnName: 'owner')
  final String owner;

  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;

  @OrmField(columnName: 'created_at')
  final DateTime createdAt;
}
