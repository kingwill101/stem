import 'package:ormed/ormed.dart';

part 'stem_worker_heartbeat.orm.dart';

/// Database model for worker heartbeat records.
@OrmModel(table: 'stem_worker_heartbeats')
class StemWorkerHeartbeat extends Model<StemWorkerHeartbeat>
    with TimestampsTZ, SoftDeletesTZ {
  /// Creates a worker heartbeat record.
  const StemWorkerHeartbeat({
    required this.workerId,
    required this.namespace,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    required this.version,
    required this.extras,
    required this.expiresAt,
    this.lastLeaseRenewal,
  });

  /// Worker identifier.
  @OrmField(columnName: 'worker_id', isPrimaryKey: true)
  final String workerId;

  /// Namespace reported by the worker.
  final String namespace;

  /// Timestamp of the heartbeat.
  final DateTime timestamp;

  /// Number of isolates reported by the worker.
  @OrmField(columnName: 'isolate_count')
  final int isolateCount;

  /// Number of inflight jobs across queues.
  final int inflight;

  // Store as map to align with JSON codec expectations
  /// Queue heartbeat payload stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> queues;

  /// Timestamp of the last lease renewal, if tracked.
  @OrmField(columnName: 'last_lease_renewal')
  final DateTime? lastLeaseRenewal;

  /// Worker version string.
  final String version;

  /// Additional metadata stored as JSON.
  @OrmField(cast: 'json')
  final Map<String, Object?> extras;

  /// Timestamp when the heartbeat expires.
  @OrmField(columnName: 'expires_at')
  final DateTime expiresAt;
}
