import 'package:stem/stem.dart' show QueueHeartbeat, WorkerHeartbeat;

class QueueSummary {
  const QueueSummary({
    required this.queue,
    required this.pending,
    required this.inflight,
    required this.deadLetters,
  });

  final String queue;
  final int pending;
  final int inflight;
  final int deadLetters;

  int get total => pending + inflight;
}

class WorkerQueueInfo {
  const WorkerQueueInfo({required this.name, required this.inflight});

  factory WorkerQueueInfo.fromJson(Map<String, Object?> json) {
    return WorkerQueueInfo(
      name: json['name'] as String? ?? 'default',
      inflight: (json['inflight'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final int inflight;

  factory WorkerQueueInfo.fromHeartbeat(QueueHeartbeat heartbeat) {
    return WorkerQueueInfo(name: heartbeat.name, inflight: heartbeat.inflight);
  }
}

class WorkerStatus {
  WorkerStatus({
    required this.workerId,
    required this.namespace,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    Map<String, Object?>? extras,
  }) : extras = extras ?? const {};

  factory WorkerStatus.fromJson(Map<String, Object?> json) {
    final queues =
        (json['queues'] as List<dynamic>?)
            ?.map(
              (entry) => WorkerQueueInfo.fromJson(
                (entry as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false) ??
        const <WorkerQueueInfo>[];

    return WorkerStatus(
      workerId: json['workerId'] as String? ?? 'unknown',
      namespace: json['namespace'] as String? ?? 'stem',
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      isolateCount: (json['isolateCount'] as num?)?.toInt() ?? 0,
      inflight: (json['inflight'] as num?)?.toInt() ?? 0,
      queues: queues,
      extras: (json['extras'] as Map?)?.cast<String, Object?>(),
    );
  }

  factory WorkerStatus.fromHeartbeat(WorkerHeartbeat heartbeat) {
    final queues = heartbeat.queues
        .map(WorkerQueueInfo.fromHeartbeat)
        .toList(growable: false);
    return WorkerStatus(
      workerId: heartbeat.workerId,
      namespace: heartbeat.namespace,
      timestamp: heartbeat.timestamp.toUtc(),
      isolateCount: heartbeat.isolateCount,
      inflight: heartbeat.inflight,
      queues: queues,
      extras: heartbeat.extras,
    );
  }

  final String workerId;
  final String namespace;
  final DateTime timestamp;
  final int isolateCount;
  final int inflight;
  final List<WorkerQueueInfo> queues;
  final Map<String, Object?> extras;

  Duration get age => DateTime.now().toUtc().difference(timestamp);
}

class DashboardEvent {
  DashboardEvent({
    required this.title,
    required this.timestamp,
    this.summary,
    this.metadata = const {},
  });

  final String title;
  final DateTime timestamp;
  final String? summary;
  final Map<String, Object?> metadata;
}

class EnqueueRequest {
  EnqueueRequest({
    required this.queue,
    required this.task,
    Map<String, Object?>? args,
    this.priority = 0,
    this.maxRetries = 0,
  }) : args = args ?? const {};

  final String queue;
  final String task;
  final Map<String, Object?> args;
  final int priority;
  final int maxRetries;
}
