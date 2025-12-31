import 'package:stem/stem.dart' show QueueHeartbeat, WorkerHeartbeat;

/// Aggregate counts for a queue at a point in time.
class QueueSummary {
  /// Creates a queue summary snapshot.
  const QueueSummary({
    required this.queue,
    required this.pending,
    required this.inflight,
    required this.deadLetters,
  });

  /// Queue name.
  final String queue;

  /// Number of pending jobs in the queue.
  final int pending;

  /// Number of inflight jobs currently being processed.
  final int inflight;

  /// Number of dead letter jobs for the queue.
  final int deadLetters;

  /// Total count of pending plus inflight jobs.
  int get total => pending + inflight;
}

/// Throughput summary derived from a polling interval.
class DashboardThroughput {
  /// Creates throughput metrics for a polling interval.
  const DashboardThroughput({
    required this.interval,
    required this.processed,
    required this.enqueued,
  });

  /// Interval used to compute the throughput values.
  final Duration interval;

  /// Number of items processed in [interval].
  final int processed;

  /// Number of items enqueued in [interval].
  final int enqueued;

  /// Processed items per minute based on [interval].
  double get processedPerMinute => _perMinute(processed);

  /// Enqueued items per minute based on [interval].
  double get enqueuedPerMinute => _perMinute(enqueued);

  double _perMinute(int count) {
    if (interval.inMilliseconds <= 0) return 0;
    return count / interval.inMilliseconds * 60000;
  }
}

/// Queue details reported by a worker heartbeat.
class WorkerQueueInfo {
  /// Creates queue info for a worker heartbeat.
  const WorkerQueueInfo({required this.name, required this.inflight});

  /// Creates queue info from a queue heartbeat entry.
  factory WorkerQueueInfo.fromHeartbeat(QueueHeartbeat heartbeat) {
    return WorkerQueueInfo(name: heartbeat.name, inflight: heartbeat.inflight);
  }

  /// Creates queue info from a JSON map.
  factory WorkerQueueInfo.fromJson(Map<String, Object?> json) {
    return WorkerQueueInfo(
      name: json['name'] as String? ?? 'default',
      inflight: (json['inflight'] as num?)?.toInt() ?? 0,
    );
  }

  /// Queue name.
  final String name;

  /// Number of inflight jobs for this queue.
  final int inflight;
}

/// Current status for a worker instance.
class WorkerStatus {
  /// Creates a worker status snapshot.
  WorkerStatus({
    required this.workerId,
    required this.namespace,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    Map<String, Object?>? extras,
  }) : extras = extras ?? const {};

  /// Creates a worker status from a JSON map.
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
      timestamp: DateTime.parse(json['timestamp']! as String).toUtc(),
      isolateCount: (json['isolateCount'] as num?)?.toInt() ?? 0,
      inflight: (json['inflight'] as num?)?.toInt() ?? 0,
      queues: queues,
      extras: (json['extras'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Creates a worker status from a worker heartbeat.
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

  /// Worker identifier.
  final String workerId;

  /// Namespace reported by the worker.
  final String namespace;

  /// Timestamp of the most recent heartbeat.
  final DateTime timestamp;

  /// Number of isolates reported by the worker.
  final int isolateCount;

  /// Number of inflight jobs across all queues.
  final int inflight;

  /// Queues reported by the worker.
  final List<WorkerQueueInfo> queues;

  /// Additional metadata reported by the worker.
  final Map<String, Object?> extras;

  /// Age of the last heartbeat.
  Duration get age => DateTime.now().toUtc().difference(timestamp);
}

/// Event captured for the dashboard activity log.
class DashboardEvent {
  /// Creates a dashboard event entry.
  DashboardEvent({
    required this.title,
    required this.timestamp,
    this.summary,
    this.metadata = const {},
  });

  /// Title shown in the event feed.
  final String title;

  /// Timestamp for the event.
  final DateTime timestamp;

  /// Optional summary shown under the title.
  final String? summary;

  /// Optional key/value metadata rendered with the event.
  final Map<String, Object?> metadata;
}

/// Task request submitted from the dashboard UI.
class EnqueueRequest {
  /// Creates a task enqueue request.
  EnqueueRequest({
    required this.queue,
    required this.task,
    Map<String, Object?>? args,
    this.priority = 0,
    this.maxRetries = 0,
  }) : args = args ?? const {};

  /// Queue name to publish to.
  final String queue;

  /// Task name to enqueue.
  final String task;

  /// Arguments supplied to the task.
  final Map<String, Object?> args;

  /// Priority assigned to the task.
  final int priority;

  /// Maximum retry count for the task.
  final int maxRetries;
}
