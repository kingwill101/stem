import 'package:ormed/ormed.dart';

part 'stem_revoke_entry.orm.dart';

/// Database model for persisted revoke entries.
@OrmModel(table: 'stem_revokes', primaryKey: ['namespace', 'taskId'])
class StemRevokeEntry extends Model<StemRevokeEntry> with TimestampsTZ {
  /// Creates a revoke entry record.
  const StemRevokeEntry({
    required this.namespace,
    required this.taskId,
    required this.version,
    required this.issuedAt,
    required this.terminate,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });

  /// Namespace that owns the revoke record.
  final String namespace;

  /// Task identifier for the revoke record.
  @OrmField(columnName: 'task_id')
  final String taskId;

  /// Monotonic version of the revoke record.
  final int version;

  /// Timestamp when the revoke was issued.
  @OrmField(columnName: 'issued_at')
  final DateTime issuedAt;

  /// Integer flag representing terminate intent (`1` means true).
  final int terminate;

  /// Optional human-readable reason.
  final String? reason;

  /// Optional caller identity.
  @OrmField(columnName: 'requested_by')
  final String? requestedBy;

  /// Optional expiration timestamp.
  @OrmField(columnName: 'expires_at')
  final DateTime? expiresAt;
}
