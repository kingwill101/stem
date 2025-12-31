import 'package:ormed/ormed.dart';

part 'stem_lock.orm.dart';

/// Database model for advisory locks.
@OrmModel(table: 'stem_locks')
class StemLock extends Model<StemLock> {
  /// Creates a lock record.
  StemLock({
    required this.key,
    required this.owner,
    required this.expiresAt,
    required this.createdAt,
  });

  /// Lock key.
  @OrmField(columnName: 'key', isPrimaryKey: true)
  final String key;

  /// Owner identifier for the lock.
  @OrmField(columnName: 'owner')
  final String owner;

  /// Timestamp when the lock expires.
  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;

  /// Timestamp when the lock was created.
  @OrmField(columnName: 'created_at')
  final DateTime createdAt;
}
