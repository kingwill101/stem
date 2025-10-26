import 'dart:convert';

/// Structured payload describing worker state for external monitoring systems.
class WorkerHeartbeat {
  /// Captures the current worker state at [timestamp] using optional [extras].
  WorkerHeartbeat({
    required this.workerId,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    this.lastLeaseRenewal,
    this.version = currentVersion,
    this.namespace = 'stem',
    Map<String, Object?>? extras,
  }) : extras = Map.unmodifiable(extras ?? const {});

  /// Static version identifier for the heartbeat schema.
  static const currentVersion = '1';

  /// Logical worker identifier (typically the consumer/worker name).
  final String workerId;

  /// Namespace used for routing (e.g. Redis channel prefix).
  final String namespace;

  /// Timestamp for when this heartbeat was generated.
  final DateTime timestamp;

  /// Number of isolates currently active in the worker pool.
  final int isolateCount;

  /// Total number of deliveries currently in-flight for this worker.
  final int inflight;

  /// Optional timestamp of the most recent lease renewal across in-flight
  /// deliveries.
  final DateTime? lastLeaseRenewal;

  /// Semantic version of the payload structure.
  final String version;

  /// Queue level detail for in-flight deliveries.
  final List<QueueHeartbeat> queues;

  /// Additional metadata for downstream consumers.
  final Map<String, Object?> extras;

  /// Serializes this heartbeat into a JSON-ready map for transport or storage.
  Map<String, Object?> toJson() => {
    'workerId': workerId,
    'namespace': namespace,
    'timestamp': timestamp.toIso8601String(),
    'isolateCount': isolateCount,
    'inflight': inflight,
    'lastLeaseRenewal': lastLeaseRenewal?.toIso8601String(),
    'version': version,
    'queues': queues.map((queue) => queue.toJson()).toList(),
    'extras': extras,
  };

  /// Rehydrates a [WorkerHeartbeat] from the JSON [json] map.
  factory WorkerHeartbeat.fromJson(Map<String, Object?> json) {
    return WorkerHeartbeat(
      workerId: json['workerId'] as String,
      namespace: (json['namespace'] as String?) ?? 'stem',
      timestamp: DateTime.parse(json['timestamp'] as String),
      isolateCount: (json['isolateCount'] as num).toInt(),
      inflight: (json['inflight'] as num).toInt(),
      lastLeaseRenewal: json['lastLeaseRenewal'] != null
          ? DateTime.parse(json['lastLeaseRenewal'] as String)
          : null,
      version: json['version'] as String? ?? currentVersion,
      queues: (json['queues'] as List<dynamic>? ?? const [])
          .map(
            (queue) =>
                QueueHeartbeat.fromJson((queue as Map).cast<String, Object?>()),
          )
          .toList(),
      extras: (json['extras'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// Encode the heartbeat as a JSON string for transport.
  String encode() => jsonEncode(toJson());

  /// Convenience helper producing the Redis topic for the provided [namespace].
  static String topic(String namespace) => 'stem:heartbeat:$namespace';
}

/// Aggregated in-flight counts for a specific queue.
class QueueHeartbeat {
  /// Describes the current in-flight delivery count for [name].
  QueueHeartbeat({required this.name, required this.inflight});

  /// Queue identifier used in downstream monitoring.
  final String name;

  /// In-flight delivery count for this queue at the sampled instant.
  final int inflight;

  /// Serializes this queue heartbeat into a JSON-ready map.
  Map<String, Object?> toJson() => {'name': name, 'inflight': inflight};

  /// Recreates a [QueueHeartbeat] from a JSON [json] map.
  factory QueueHeartbeat.fromJson(Map<String, Object?> json) {
    return QueueHeartbeat(
      name: json['name'] as String,
      inflight: (json['inflight'] as num).toInt(),
    );
  }
}
