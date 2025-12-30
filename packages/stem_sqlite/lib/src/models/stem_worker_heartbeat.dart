import 'package:ormed/ormed.dart';

part 'stem_worker_heartbeat.orm.dart';

@OrmModel(table: 'stem_worker_heartbeats')
class StemWorkerHeartbeat extends Model<StemWorkerHeartbeat>
    with TimestampsTZ, SoftDeletesTZ {
  const StemWorkerHeartbeat({
    required this.workerId,
    required this.namespace,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    this.lastLeaseRenewal,
    required this.version,
    required this.extras,
    required this.expiresAt,
  });

  @OrmField(columnName: 'worker_id', isPrimaryKey: true)
  final String workerId;

  final String namespace;
  final DateTime timestamp;

  @OrmField(columnName: 'isolate_count')
  final int isolateCount;

  final int inflight;
  @OrmField(cast: 'json')
  final Map<String, Object?> queues;

  @OrmField(columnName: 'last_lease_renewal')
  final DateTime? lastLeaseRenewal;

  final String version;
  @OrmField(cast: 'json')
  final Map<String, Object?> extras;

  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;
}
