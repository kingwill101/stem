import 'dart:convert';
import 'dart:io';

class QueueSnapshot {
  QueueSnapshot({
    required this.queue,
    required this.pending,
    required this.inflight,
  });

  final String queue;
  final int pending;
  final int inflight;

  Map<String, Object> toJson() => {
    'queue': queue,
    'pending': pending,
    'inflight': inflight,
  };

  factory QueueSnapshot.fromJson(Map<String, Object?> json) => QueueSnapshot(
    queue: json['queue'] as String,
    pending: (json['pending'] as num).toInt(),
    inflight: (json['inflight'] as num).toInt(),
  );
}

class WorkerSnapshot {
  WorkerSnapshot({
    required this.id,
    required this.active,
    required this.lastHeartbeat,
  });

  final String id;
  final int active;
  final DateTime lastHeartbeat;

  Map<String, Object> toJson() => {
    'id': id,
    'active': active,
    'lastHeartbeat': lastHeartbeat.toIso8601String(),
  };

  factory WorkerSnapshot.fromJson(Map<String, Object?> json) => WorkerSnapshot(
    id: json['id'] as String,
    active: (json['active'] as num).toInt(),
    lastHeartbeat: DateTime.parse(json['lastHeartbeat'] as String),
  );
}

class DlqEntrySnapshot {
  DlqEntrySnapshot({
    required this.queue,
    required this.taskId,
    required this.reason,
    required this.deadAt,
  });

  final String queue;
  final String taskId;
  final String reason;
  final DateTime deadAt;

  Map<String, Object> toJson() => {
    'queue': queue,
    'taskId': taskId,
    'reason': reason,
    'deadAt': deadAt.toIso8601String(),
  };

  factory DlqEntrySnapshot.fromJson(Map<String, Object?> json) =>
      DlqEntrySnapshot(
        queue: json['queue'] as String,
        taskId: json['taskId'] as String,
        reason: json['reason'] as String,
        deadAt: DateTime.parse(json['deadAt'] as String),
      );
}

class ObservabilityReport {
  ObservabilityReport({
    this.queues = const [],
    this.workers = const [],
    this.dlq = const [],
  });

  final List<QueueSnapshot> queues;
  final List<WorkerSnapshot> workers;
  final List<DlqEntrySnapshot> dlq;

  Map<String, Object> toJson() => {
    'queues': queues.map((q) => q.toJson()).toList(),
    'workers': workers.map((w) => w.toJson()).toList(),
    'dlq': dlq.map((d) => d.toJson()).toList(),
  };

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
