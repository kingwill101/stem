import 'package:stem/stem.dart'
    show
        QueueHeartbeat,
        RunState,
        TaskState,
        TaskStatus,
        TaskStatusRecord,
        WorkerHeartbeat,
        WorkflowStatus,
        WorkflowStepEntry,
        stemNow;

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
  Duration get age => stemNow().toUtc().difference(timestamp);
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

/// Audit log entry for operator actions and automated alerts.
class DashboardAuditEntry {
  /// Creates an audit log entry.
  const DashboardAuditEntry({
    required this.id,
    required this.timestamp,
    required this.kind,
    required this.action,
    required this.status,
    this.actor,
    this.summary,
    this.metadata = const {},
  });

  /// Stable entry identifier.
  final String id;

  /// Event timestamp.
  final DateTime timestamp;

  /// Entry kind: `action` or `alert`.
  final String kind;

  /// Action/event type identifier.
  final String action;

  /// Status marker (`ok`, `error`, `sent`, `skipped`, etc.).
  final String status;

  /// Actor identifier where applicable.
  final String? actor;

  /// Human-readable summary.
  final String? summary;

  /// Optional metadata payload.
  final Map<String, Object?> metadata;
}

/// Dashboard-friendly projection of a persisted task status record.
class DashboardTaskStatusEntry {
  /// Creates a task status entry.
  const DashboardTaskStatusEntry({
    required this.id,
    required this.state,
    required this.attempt,
    required this.createdAt,
    required this.updatedAt,
    required this.queue,
    required this.taskName,
    this.errorMessage,
    this.errorType,
    this.errorStack,
    this.payload,
    this.meta = const {},
    this.runId,
    this.workflowName,
    this.workflowStep,
    this.workflowStepIndex,
    this.workflowIteration,
    this.retryable = false,
  });

  /// Builds a dashboard task entry from a [TaskStatusRecord].
  factory DashboardTaskStatusEntry.fromRecord(TaskStatusRecord record) {
    final status = record.status;
    final meta = status.meta;
    final error = status.error;
    final queue = _readQueue(meta);
    final taskName = _readTaskName(meta);
    return DashboardTaskStatusEntry(
      id: status.id,
      state: status.state,
      attempt: status.attempt,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      queue: queue,
      taskName: taskName,
      errorMessage: error?.message,
      errorType: error?.type,
      errorStack: error?.stack,
      payload: status.payload,
      meta: meta,
      runId: meta['stem.workflow.runId']?.toString(),
      workflowName: meta['stem.workflow.name']?.toString(),
      workflowStep: meta['stem.workflow.step']?.toString(),
      workflowStepIndex: _readInt(meta['stem.workflow.stepIndex']),
      workflowIteration: _readInt(meta['stem.workflow.iteration']),
      retryable: error?.retryable ?? false,
    );
  }

  /// Builds a dashboard task entry from a plain [TaskStatus].
  ///
  /// Use this when the result backend can return the current status but not
  /// the persisted record timestamps.
  factory DashboardTaskStatusEntry.fromStatus(
    TaskStatus status, {
    DateTime? observedAt,
  }) {
    final seenAt = observedAt?.toUtc() ?? stemNow().toUtc();
    final meta = status.meta;
    final queue = _readQueue(meta);
    final taskName = _readTaskName(meta);
    final error = status.error;
    return DashboardTaskStatusEntry(
      id: status.id,
      state: status.state,
      attempt: status.attempt,
      createdAt: seenAt,
      updatedAt: seenAt,
      queue: queue,
      taskName: taskName,
      errorMessage: error?.message,
      errorType: error?.type,
      errorStack: error?.stack,
      payload: status.payload,
      meta: meta,
      runId: meta['stem.workflow.runId']?.toString(),
      workflowName: meta['stem.workflow.name']?.toString(),
      workflowStep: meta['stem.workflow.step']?.toString(),
      workflowStepIndex: _readInt(meta['stem.workflow.stepIndex']),
      workflowIteration: _readInt(meta['stem.workflow.iteration']),
      retryable: error?.retryable ?? false,
    );
  }

  /// Task identifier.
  final String id;

  /// Current lifecycle state.
  final TaskState state;

  /// Attempt count for this status.
  final int attempt;

  /// Record creation timestamp.
  final DateTime createdAt;

  /// Record update timestamp.
  final DateTime updatedAt;

  /// Queue associated with the task.
  final String queue;

  /// Task handler name if available.
  final String taskName;

  /// Failure message when [state] is failed/retried.
  final String? errorMessage;

  /// Failure type when [state] is failed/retried.
  final String? errorType;

  /// Failure stack trace when captured by the backend.
  final String? errorStack;

  /// Persisted task result payload.
  final Object? payload;

  /// Raw task metadata from the result backend.
  final Map<String, Object?> meta;

  /// Workflow run identifier, when this task is part of a workflow.
  final String? runId;

  /// Workflow name, when present.
  final String? workflowName;

  /// Workflow step name, when present.
  final String? workflowStep;

  /// Workflow step index, when present.
  final int? workflowStepIndex;

  /// Workflow iteration, when present.
  final int? workflowIteration;

  /// Whether the failure is marked retryable.
  final bool retryable;

  /// Namespace reported by task metadata, or `stem` when unavailable.
  String get namespace => _readNamespace(meta);

  /// Whether this entry represents a workflow task.
  bool get isWorkflowTask =>
      runId != null ||
      taskName.startsWith('stem.workflow.') ||
      taskName.contains('workflow');

  /// Whether this entry is in a failed terminal state.
  bool get isFailure =>
      state == TaskState.failed || state == TaskState.cancelled;

  /// Fingerprint used to group related failures in diagnostics views.
  String get errorFingerprint {
    final type = (errorType ?? 'Unknown').trim();
    final message = (errorMessage ?? 'No message').trim();
    return '$type: $message';
  }

  /// Task processing start timestamp, when recorded by workers.
  DateTime? get startedAt => _readDate(meta['startedAt']);

  /// Task completion/failure timestamp, when recorded by workers.
  DateTime? get finishedAt =>
      _readDate(meta['completedAt']) ?? _readDate(meta['failedAt']);

  /// Estimated queue wait from persisted record creation to processing start.
  Duration? get queueWait {
    final started = startedAt;
    if (started == null) return null;
    final value = started.difference(createdAt.toUtc());
    if (value.isNegative) return Duration.zero;
    return value;
  }

  /// Estimated processing time from start to finish/last update.
  Duration? get processingTime {
    final started = startedAt;
    if (started == null) return null;
    final end = finishedAt ?? updatedAt.toUtc();
    final value = end.difference(started);
    if (value.isNegative) return Duration.zero;
    return value;
  }
}

/// App-focused namespace summary for dashboard observability.
class DashboardNamespaceSnapshot {
  /// Creates a namespace summary.
  const DashboardNamespaceSnapshot({
    required this.namespace,
    required this.queueCount,
    required this.workerCount,
    required this.pending,
    required this.inflight,
    required this.deadLetters,
    required this.runningTasks,
    required this.failedTasks,
    required this.workflowRuns,
  });

  /// Namespace identifier.
  final String namespace;

  /// Number of distinct queues seen for this namespace.
  final int queueCount;

  /// Number of active workers in this namespace.
  final int workerCount;

  /// Pending queue depth.
  final int pending;

  /// In-flight envelope count.
  final int inflight;

  /// Dead-letter count.
  final int deadLetters;

  /// Running task statuses.
  final int runningTasks;

  /// Failed terminal task statuses.
  final int failedTasks;

  /// Distinct workflow run ids observed in task metadata.
  final int workflowRuns;
}

/// Aggregate task summary grouped by task name.
class DashboardJobSummary {
  /// Creates a task/job summary.
  const DashboardJobSummary({
    required this.taskName,
    required this.sampleQueue,
    required this.total,
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.retried,
    required this.cancelled,
    required this.lastUpdated,
  });

  /// Task handler name.
  final String taskName;

  /// Queue most commonly associated with this task in sampled statuses.
  final String sampleQueue;

  /// Total sampled statuses for this task.
  final int total;

  /// Running count.
  final int running;

  /// Success count.
  final int succeeded;

  /// Failure count.
  final int failed;

  /// Retried count.
  final int retried;

  /// Cancelled count.
  final int cancelled;

  /// Most recent update timestamp across sampled statuses.
  final DateTime lastUpdated;

  /// Failure ratio in sampled statuses.
  double get failureRatio => total <= 0 ? 0 : failed / total;
}

/// Workflow run summary projected from task status metadata.
class DashboardWorkflowRunSummary {
  /// Creates a workflow summary.
  const DashboardWorkflowRunSummary({
    required this.runId,
    required this.workflowName,
    required this.lastStep,
    required this.total,
    required this.queued,
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.cancelled,
    required this.lastUpdated,
  });

  /// Workflow run id.
  final String runId;

  /// Workflow name, when available.
  final String workflowName;

  /// Most recent step marker, when available.
  final String? lastStep;

  /// Total sampled statuses for this run.
  final int total;

  /// Queued count.
  final int queued;

  /// Running count.
  final int running;

  /// Succeeded count.
  final int succeeded;

  /// Failed count.
  final int failed;

  /// Cancelled count.
  final int cancelled;

  /// Most recent update timestamp.
  final DateTime lastUpdated;
}

/// Builds app-focused namespace summaries from sampled runtime state.
List<DashboardNamespaceSnapshot> buildNamespaceSnapshots({
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  required List<DashboardTaskStatusEntry> tasks,
  String defaultNamespace = 'stem',
}) {
  final queueNamesByNamespace = <String, Set<String>>{};
  final pendingByNamespace = <String, int>{};
  final inflightByNamespace = <String, int>{};
  final deadByNamespace = <String, int>{};
  final workerCountByNamespace = <String, int>{};
  final runningByNamespace = <String, int>{};
  final failedByNamespace = <String, int>{};
  final runsByNamespace = <String, Set<String>>{};

  for (final queue in queues) {
    queueNamesByNamespace.putIfAbsent(defaultNamespace, () => <String>{}).add(
      queue.queue,
    );
    pendingByNamespace[defaultNamespace] =
        (pendingByNamespace[defaultNamespace] ?? 0) + queue.pending;
    inflightByNamespace[defaultNamespace] =
        (inflightByNamespace[defaultNamespace] ?? 0) + queue.inflight;
    deadByNamespace[defaultNamespace] =
        (deadByNamespace[defaultNamespace] ?? 0) + queue.deadLetters;
  }

  for (final worker in workers) {
    final namespace = worker.namespace.trim().isEmpty
        ? defaultNamespace
        : worker.namespace.trim();
    workerCountByNamespace[namespace] =
        (workerCountByNamespace[namespace] ?? 0) + 1;
    final names = queueNamesByNamespace.putIfAbsent(
      namespace,
      () => <String>{},
    );
    for (final queue in worker.queues) {
      names.add(queue.name);
    }
  }

  for (final task in tasks) {
    final namespace = task.namespace.trim().isEmpty
        ? defaultNamespace
        : task.namespace.trim();
    queueNamesByNamespace.putIfAbsent(namespace, () => <String>{}).add(
      task.queue,
    );
    if (task.state == TaskState.running) {
      runningByNamespace[namespace] = (runningByNamespace[namespace] ?? 0) + 1;
    }
    if (task.isFailure) {
      failedByNamespace[namespace] = (failedByNamespace[namespace] ?? 0) + 1;
    }
    if (task.runId != null && task.runId!.isNotEmpty) {
      runsByNamespace.putIfAbsent(namespace, () => <String>{}).add(task.runId!);
    }
  }

  final namespaces = <String>{
    ...queueNamesByNamespace.keys,
    ...workerCountByNamespace.keys,
    ...runningByNamespace.keys,
    ...failedByNamespace.keys,
    ...runsByNamespace.keys,
  }.toList(growable: false)
    ..sort();

  return namespaces.map((namespace) {
    return DashboardNamespaceSnapshot(
      namespace: namespace,
      queueCount: queueNamesByNamespace[namespace]?.length ?? 0,
      workerCount: workerCountByNamespace[namespace] ?? 0,
      pending: pendingByNamespace[namespace] ?? 0,
      inflight: inflightByNamespace[namespace] ?? 0,
      deadLetters: deadByNamespace[namespace] ?? 0,
      runningTasks: runningByNamespace[namespace] ?? 0,
      failedTasks: failedByNamespace[namespace] ?? 0,
      workflowRuns: runsByNamespace[namespace]?.length ?? 0,
    );
  }).toList(growable: false);
}

/// Builds task/job summaries grouped by task name.
List<DashboardJobSummary> buildJobSummaries(
  List<DashboardTaskStatusEntry> tasks, {
  int limit = 20,
}) {
  final buckets = <String, _DashboardJobSummaryBuilder>{};
  for (final task in tasks) {
    buckets
        .putIfAbsent(
          task.taskName,
          () => _DashboardJobSummaryBuilder(taskName: task.taskName),
        )
        .add(task);
  }
  final results = buckets.values.map((bucket) => bucket.build()).toList()
    ..sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });
  final bounded = limit < 1 ? 1 : limit;
  return results.take(bounded).toList(growable: false);
}

/// Builds workflow run summaries grouped by run id.
List<DashboardWorkflowRunSummary> buildWorkflowRunSummaries(
  List<DashboardTaskStatusEntry> tasks, {
  int limit = 20,
}) {
  final buckets = <String, _DashboardWorkflowSummaryBuilder>{};
  for (final task in tasks) {
    final runId = task.runId?.trim();
    if (runId == null || runId.isEmpty) continue;
    buckets
        .putIfAbsent(runId, () => _DashboardWorkflowSummaryBuilder(runId))
        .add(task);
  }
  final results = buckets.values.map((bucket) => bucket.build()).toList()
    ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
  final bounded = limit < 1 ? 1 : limit;
  return results.take(bounded).toList(growable: false);
}

/// Projection of a workflow run snapshot for dashboard rendering.
class DashboardWorkflowRunSnapshot {
  /// Creates a workflow run snapshot.
  const DashboardWorkflowRunSnapshot({
    required this.id,
    required this.workflow,
    required this.status,
    required this.cursor,
    required this.createdAt,
    this.updatedAt,
    this.waitTopic,
    this.resumeAt,
    this.ownerId,
    this.leaseExpiresAt,
    this.lastError,
    this.result,
  });

  /// Builds a dashboard workflow run snapshot from [RunState].
  factory DashboardWorkflowRunSnapshot.fromRunState(RunState state) {
    return DashboardWorkflowRunSnapshot(
      id: state.id,
      workflow: state.workflow,
      status: state.status,
      cursor: state.cursor,
      createdAt: state.createdAt,
      updatedAt: state.updatedAt,
      waitTopic: state.waitTopic,
      resumeAt: state.resumeAt,
      ownerId: state.ownerId,
      leaseExpiresAt: state.leaseExpiresAt,
      lastError: state.lastError,
      result: state.result,
    );
  }

  /// Run identifier.
  final String id;

  /// Workflow name.
  final String workflow;

  /// Current lifecycle state.
  final WorkflowStatus status;

  /// Next step cursor.
  final int cursor;

  /// Run creation timestamp.
  final DateTime createdAt;

  /// Most recent mutation timestamp.
  final DateTime? updatedAt;

  /// Topic currently awaited by this run, when suspended.
  final String? waitTopic;

  /// Resume deadline for suspended runs.
  final DateTime? resumeAt;

  /// Owner of the active lease when running.
  final String? ownerId;

  /// Lease expiration if the run is claimed.
  final DateTime? leaseExpiresAt;

  /// Last error payload recorded by the workflow runtime.
  final Map<String, Object?>? lastError;

  /// Final workflow result payload when completed.
  final Object? result;
}

/// Projection of a persisted workflow step checkpoint.
class DashboardWorkflowStepSnapshot {
  /// Creates a workflow step snapshot.
  const DashboardWorkflowStepSnapshot({
    required this.name,
    required this.position,
    required this.value,
    this.completedAt,
  });

  /// Builds a workflow step snapshot from [WorkflowStepEntry].
  factory DashboardWorkflowStepSnapshot.fromEntry(WorkflowStepEntry entry) {
    return DashboardWorkflowStepSnapshot(
      name: entry.name,
      position: entry.position,
      value: entry.value,
      completedAt: entry.completedAt,
    );
  }

  /// Step name.
  final String name;

  /// Step ordering position.
  final int position;

  /// Persisted checkpoint value.
  final Object? value;

  /// Completion timestamp if available.
  final DateTime? completedAt;
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

int? _readInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _readDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

String _readTaskName(Map<String, Object?> meta) {
  return meta['task']?.toString() ??
      meta['stem.task']?.toString() ??
      meta['name']?.toString() ??
      meta['taskName']?.toString() ??
      'unknown';
}

String _readQueue(Map<String, Object?> meta) {
  return meta['queue']?.toString() ??
      meta['stem.queue']?.toString() ??
      'default';
}

String _readNamespace(Map<String, Object?> meta) {
  return meta['namespace']?.toString() ??
      meta['stem.namespace']?.toString() ??
      'stem';
}

class _DashboardJobSummaryBuilder {
  _DashboardJobSummaryBuilder({required this.taskName});

  final String taskName;
  final Map<String, int> _queueHits = {};
  var _total = 0;
  var _running = 0;
  var _succeeded = 0;
  var _failed = 0;
  var _retried = 0;
  var _cancelled = 0;
  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void add(DashboardTaskStatusEntry task) {
    _total += 1;
    _queueHits[task.queue] = (_queueHits[task.queue] ?? 0) + 1;
    if (task.state == TaskState.running) _running += 1;
    if (task.state == TaskState.succeeded) _succeeded += 1;
    if (task.state == TaskState.failed) _failed += 1;
    if (task.state == TaskState.retried) _retried += 1;
    if (task.state == TaskState.cancelled) _cancelled += 1;
    if (task.updatedAt.toUtc().isAfter(_lastUpdated)) {
      _lastUpdated = task.updatedAt.toUtc();
    }
  }

  DashboardJobSummary build() {
    final sampleQueue = _queueHits.entries.isEmpty
        ? 'default'
        : (_queueHits.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    return DashboardJobSummary(
      taskName: taskName,
      sampleQueue: sampleQueue,
      total: _total,
      running: _running,
      succeeded: _succeeded,
      failed: _failed,
      retried: _retried,
      cancelled: _cancelled,
      lastUpdated: _lastUpdated,
    );
  }
}

class _DashboardWorkflowSummaryBuilder {
  _DashboardWorkflowSummaryBuilder(this.runId);

  final String runId;
  String _workflowName = 'workflow';
  String? _lastStep;
  var _total = 0;
  var _queued = 0;
  var _running = 0;
  var _succeeded = 0;
  var _failed = 0;
  var _cancelled = 0;
  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void add(DashboardTaskStatusEntry task) {
    _total += 1;
    if (task.workflowName != null && task.workflowName!.isNotEmpty) {
      _workflowName = task.workflowName!;
    }
    if (task.workflowStep != null && task.workflowStep!.isNotEmpty) {
      _lastStep = task.workflowStep;
    }
    if (task.state == TaskState.queued || task.state == TaskState.retried) {
      _queued += 1;
    }
    if (task.state == TaskState.running) _running += 1;
    if (task.state == TaskState.succeeded) _succeeded += 1;
    if (task.state == TaskState.failed) _failed += 1;
    if (task.state == TaskState.cancelled) _cancelled += 1;
    if (task.updatedAt.toUtc().isAfter(_lastUpdated)) {
      _lastUpdated = task.updatedAt.toUtc();
    }
  }

  DashboardWorkflowRunSummary build() {
    return DashboardWorkflowRunSummary(
      runId: runId,
      workflowName: _workflowName,
      lastStep: _lastStep,
      total: _total,
      queued: _queued,
      running: _running,
      succeeded: _succeeded,
      failed: _failed,
      cancelled: _cancelled,
      lastUpdated: _lastUpdated,
    );
  }
}
