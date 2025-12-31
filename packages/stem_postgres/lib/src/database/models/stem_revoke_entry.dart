import 'package:ormed/ormed.dart';

part 'stem_revoke_entry.orm.dart';

/// Database model for task revoke entries.
@OrmModel(table: 'stem_revokes')
class StemRevokeEntry extends Model<StemRevokeEntry> {
  /// Creates a revoke entry record.
  StemRevokeEntry({
    required this.taskId,
    required this.namespace,
    required this.terminate,
    required this.issuedAt,
    required this.version,
    required this.updatedAt,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });

  /// Task identifier to revoke.
  @OrmField(columnName: 'task_id', isPrimaryKey: true)
  final String taskId;

  /// Namespace that owns the revoke entry.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Whether the task should be terminated immediately.
  @OrmField(columnName: 'terminate')
  final bool terminate;

  /// Optional human-readable reason for the revoke.
  @OrmField(columnName: 'reason')
  final String? reason;

  /// Optional identifier for who requested the revoke.
  @OrmField(columnName: 'requested_by')
  final String? requestedBy;

  /// Timestamp when the revoke was issued.
  @OrmField(columnName: 'issued_at')
  final DateTime issuedAt;

  /// Optional expiration time for the revoke.
  @OrmField(columnName: 'expires_at')
  final DateTime? expiresAt;

  /// Version number used to resolve update ordering.
  @OrmField(columnName: 'version')
  final int version;

  /// Timestamp for the last update to the revoke entry.
  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;
}
