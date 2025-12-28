import 'package:ormed/ormed.dart';

part 'stem_revoke_entry.orm.dart';

@OrmModel(table: 'stem_revokes')
class StemRevokeEntry extends Model<StemRevokeEntry> {
  StemRevokeEntry({
    required this.taskId,
    required this.namespace,
    required this.terminate,
    this.reason,
    this.requestedBy,
    required this.issuedAt,
    this.expiresAt,
    required this.version,
    required this.updatedAt,
  });

  @OrmField(columnName: 'task_id', isPrimaryKey: true)
  final String taskId;

  @OrmField(columnName: 'namespace')
  final String namespace;

  @OrmField(columnName: 'terminate')
  final bool terminate;

  @OrmField(columnName: 'reason')
  final String? reason;

  @OrmField(columnName: 'requested_by')
  final String? requestedBy;

  @OrmField(columnName: 'issued_at')
  final DateTime issuedAt;

  @OrmField(columnName: 'expires_at')
  final DateTime? expiresAt;

  @OrmField(columnName: 'version')
  final int version;

  @OrmField(columnName: 'updated_at')
  final DateTime updatedAt;
}
