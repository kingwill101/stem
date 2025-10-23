import 'dart:convert';
import 'dart:io';

/// Point-in-time metrics describing a specific queue.
class QueueSnapshot {
  /// Captures snapshot data with current [pending] and [inflight] counts.
  QueueSnapshot({
    required this.queue,
    required this.pending,
    required this.inflight,
  });

  /// Queue identifier.
  final String queue;

  /// Number of enqueued tasks awaiting processing.
  final int pending;

  /// Number of tasks currently in flight.
  final int inflight;

  /// Serializes this snapshot into a JSON-compatible map.
  Map<String, Object> toJson() => {
    'queue': queue,
    'pending': pending,
    'inflight': inflight,
  };

  /// Reconstructs a snapshot from JSON [json].
  factory QueueSnapshot.fromJson(Map<String, Object?> json) => QueueSnapshot(
    queue: json['queue'] as String,
    pending: (json['pending'] as num).toInt(),
    inflight: (json['inflight'] as num).toInt(),
  );
}

/// Captures details about a worker instance at the sample instant.
class WorkerSnapshot {
  /// Captures the worker's [id], active isolate count, and [lastHeartbeat].
  WorkerSnapshot({
    required this.id,
    required this.active,
    required this.lastHeartbeat,
  });

  /// Unique worker identifier.
  final String id;

  /// Number of active isolates or threads.
  final int active;

  /// Time the worker last emitted a heartbeat.
  final DateTime lastHeartbeat;

  /// Serializes this snapshot into a JSON-compatible map.
  Map<String, Object> toJson() => {
    'id': id,
    'active': active,
    'lastHeartbeat': lastHeartbeat.toIso8601String(),
  };

  /// Reconstructs a snapshot from JSON [json].
  factory WorkerSnapshot.fromJson(Map<String, Object?> json) => WorkerSnapshot(
    id: json['id'] as String,
    active: (json['active'] as num).toInt(),
    lastHeartbeat: DateTime.parse(json['lastHeartbeat'] as String),
  );
}

/// Represents a single entry captured in the dead-letter queue.
class DlqEntrySnapshot {
  /// Creates a snapshot for the failed task [taskId] and [reason].
  DlqEntrySnapshot({
    required this.queue,
    required this.taskId,
    required this.reason,
    required this.deadAt,
  });

  /// Queue that owns the dead-lettered task.
  final String queue;

  /// Unique identifier for the failed task.
  final String taskId;

  /// Failure reason reported for the task.
  final String reason;

  /// Timestamp when the task was moved to the dead-letter queue.
  final DateTime deadAt;

  /// Serializes this snapshot into a JSON-compatible map.
  Map<String, Object> toJson() => {
    'queue': queue,
    'taskId': taskId,
    'reason': reason,
    'deadAt': deadAt.toIso8601String(),
  };

  /// Reconstructs a snapshot from JSON [json].
  factory DlqEntrySnapshot.fromJson(Map<String, Object?> json) =>
      DlqEntrySnapshot(
        queue: json['queue'] as String,
        taskId: json['taskId'] as String,
        reason: json['reason'] as String,
        deadAt: DateTime.parse(json['deadAt'] as String),
      );
}

/// Aggregated observability information for queues, workers, and DLQ entries.
class ObservabilityReport {
  /// Creates a report backed by the provided snapshot collections.
  ObservabilityReport({
    this.queues = const [],
    this.workers = const [],
    this.dlq = const [],
  });

  /// Queue snapshots contained in this report.
  final List<QueueSnapshot> queues;

  /// Worker snapshots contained in this report.
  final List<WorkerSnapshot> workers;

  /// Dead-letter queue snapshots contained in this report.
  final List<DlqEntrySnapshot> dlq;

  /// Serializes this report into a JSON-compatible map.
  Map<String, Object> toJson() => {
    'queues': queues.map((q) => q.toJson()).toList(),
    'workers': workers.map((w) => w.toJson()).toList(),
    'dlq': dlq.map((d) => d.toJson()).toList(),
  };

  /// Reconstructs a report from raw JSON [json].
  factory ObservabilityReport.fromJson(
    Map<String, Object?> json,
  ) => ObservabilityReport(
    queues: (json['queues'] as List<dynamic>? ?? const [])
        .map((e) => QueueSnapshot.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    workers: (json['workers'] as List<dynamic>? ?? const [])
        .map((e) => WorkerSnapshot.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    dlq: (json['dlq'] as List<dynamic>? ?? const [])
        .map(
          (e) => DlqEntrySnapshot.fromJson((e as Map).cast<String, Object?>()),
        )
        .toList(),
  );

  /// Loads a report from [path], returning an empty report if the file
  /// is missing or empty.
  static ObservabilityReport fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return ObservabilityReport();
    }
    final content = file.readAsStringSync();
    if (content.trim().isEmpty) {
      return ObservabilityReport();
    }
    final json = jsonDecode(content) as Map<String, Object?>;
    return ObservabilityReport.fromJson(json);
  }
}
