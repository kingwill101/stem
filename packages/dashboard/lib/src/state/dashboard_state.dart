import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:stem/stem.dart' show TaskState, stemNow;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/ui/event_templates.dart';

/// Manages polling, state, and event streaming for the dashboard.
class DashboardState {
  /// Creates a dashboard state controller.
  DashboardState({
    required this.service,
    this.pollInterval = const Duration(seconds: 5),
    this.eventLimit = 200,
    this.auditLimit = 300,
    this.alertWebhookUrls = const [],
    this.alertBacklogThreshold = 500,
    this.alertFailedTaskThreshold = 25,
    this.alertOfflineWorkerThreshold = 1,
    this.alertCooldown = const Duration(minutes: 5),
  }) : hub = TurboStreamHub();

  /// Data source used to fetch queues and workers.
  final DashboardDataSource service;

  /// Turbo stream hub used to broadcast events.
  final TurboStreamHub hub;

  /// Polling interval used to refresh state.
  final Duration pollInterval;

  /// Maximum number of events retained in memory.
  final int eventLimit;

  /// Maximum number of audit entries retained in memory.
  final int auditLimit;

  /// Webhook URLs used for alert delivery.
  final List<String> alertWebhookUrls;

  /// Backlog threshold triggering an alert.
  final int alertBacklogThreshold;

  /// Failed-task threshold triggering an alert.
  final int alertFailedTaskThreshold;

  /// Offline-worker threshold triggering an alert.
  final int alertOfflineWorkerThreshold;

  /// Minimum duration between repeated alerts of the same type.
  final Duration alertCooldown;

  Timer? _timer;
  List<QueueSummary> _previousQueues = const [];
  Map<String, WorkerStatus> _previousWorkers = const {};
  String _previousQueueSignature = '';
  String _previousWorkerSignature = '';
  String _previousTaskSignature = '';
  var _hasPrimedRefresh = false;
  final _events = <DashboardEvent>[];
  final _auditEntries = <DashboardAuditEntry>[];
  final _lastAlertAt = <String, DateTime>{};
  Future<void> _polling = Future.value();
  DateTime? _lastPollAt;
  DashboardThroughput _throughput = const DashboardThroughput(
    interval: Duration.zero,
    processed: 0,
    enqueued: 0,
  );

  /// Snapshot of the event feed in reverse chronological order.
  List<DashboardEvent> get events => List.unmodifiable(_events);

  /// Most recent throughput calculation.
  DashboardThroughput get throughput => _throughput;

  /// Recent audit entries in reverse chronological order.
  List<DashboardAuditEntry> get auditEntries =>
      List.unmodifiable(_auditEntries);

  /// Starts the polling loop and emits initial state.
  Future<void> start() async {
    await _runPoll();
    _timer = Timer.periodic(pollInterval, (_) => _runPoll());
  }

  /// Stops polling and waits for in-flight work to complete.
  Future<void> dispose() async {
    _timer?.cancel();
    await _polling;
  }

  Future<void> _runPoll() {
    return _polling = _polling.then((_) => _poll()).catchError((_) {});
  }

  @visibleForTesting
  /// Runs a single polling cycle for tests.
  Future<void> runOnce() => _poll();

  Future<void> _poll() async {
    final queueFuture = service.fetchQueueSummaries();
    final workerFuture = service.fetchWorkerStatuses();
    final taskFuture = service.fetchTaskStatuses(limit: 120);

    final queues = await queueFuture;
    final workers = await workerFuture;
    final tasks = await taskFuture;
    _updateThroughput(queues);

    _generateQueueEvents(_previousQueues, queues);
    _generateWorkerEvents(_previousWorkers, {
      for (final worker in workers) worker.workerId: worker,
    });
    await _evaluateAlerts(queues: queues, workers: workers, tasks: tasks);

    final queueSignature = _queueSignature(queues);
    final workerSignature = _workerSignature(workers);
    final taskSignature = _taskSignature(tasks);
    final changed =
        queueSignature != _previousQueueSignature ||
        workerSignature != _previousWorkerSignature ||
        taskSignature != _previousTaskSignature;
    if (_hasPrimedRefresh && changed) {
      _broadcastRefreshSignal();
    }
    _hasPrimedRefresh = true;
    _previousQueueSignature = queueSignature;
    _previousWorkerSignature = workerSignature;
    _previousTaskSignature = taskSignature;

    _previousQueues = queues;
    _previousWorkers = {for (final worker in workers) worker.workerId: worker};
  }

  void _updateThroughput(List<QueueSummary> queues) {
    final now = stemNow().toUtc();
    if (_lastPollAt == null) {
      _lastPollAt = now;
      return;
    }
    final interval = now.difference(_lastPollAt!);
    if (interval.inMilliseconds <= 0) {
      _lastPollAt = now;
      return;
    }
    final prevPending = _sumPending(_previousQueues);
    final currPending = _sumPending(queues);
    final delta = currPending - prevPending;
    final processed = delta < 0 ? -delta : 0;
    final enqueued = delta > 0 ? delta : 0;
    _throughput = DashboardThroughput(
      interval: interval,
      processed: processed,
      enqueued: enqueued,
    );
    _lastPollAt = now;
  }

  int _sumPending(List<QueueSummary> queues) {
    var total = 0;
    for (final summary in queues) {
      total += summary.pending;
    }
    return total;
  }

  void _generateQueueEvents(
    List<QueueSummary> previous,
    List<QueueSummary> current,
  ) {
    final prevMap = {for (final summary in previous) summary.queue: summary};
    final now = stemNow().toUtc();
    for (final summary in current) {
      final prev = prevMap.remove(summary.queue);
      if (prev == null) {
        _recordEvent(
          DashboardEvent(
            title: 'Queue ${summary.queue} discovered',
            timestamp: now,
            summary:
                'Initial counts — pending ${summary.pending}, '
                'inflight ${summary.inflight}.',
          ),
        );
        continue;
      }

      final pendingDelta = summary.pending - prev.pending;
      final inflightDelta = summary.inflight - prev.inflight;
      final deadDelta = summary.deadLetters - prev.deadLetters;

      if (pendingDelta != 0) {
        _recordEvent(
          DashboardEvent(
            title:
                'Queue ${summary.queue} pending ${_deltaLabel(pendingDelta)}',
            timestamp: now,
            summary:
                'Pending changed from ${prev.pending} to ${summary.pending}.',
          ),
        );
      }

      if (inflightDelta != 0) {
        _recordEvent(
          DashboardEvent(
            title:
                'Queue ${summary.queue} inflight ${_deltaLabel(inflightDelta)}',
            timestamp: now,
            summary:
                'Inflight changed from ${prev.inflight} '
                'to ${summary.inflight}.',
          ),
        );
      }

      if (deadDelta != 0) {
        _recordEvent(
          DashboardEvent(
            title:
                'Queue ${summary.queue} dead letters ${_deltaLabel(deadDelta)}',
            timestamp: now,
            summary:
                'Dead letters changed from ${prev.deadLetters} '
                'to ${summary.deadLetters}.',
          ),
        );
      }
    }

    for (final removed in prevMap.values) {
      _recordEvent(
        DashboardEvent(
          title: 'Queue ${removed.queue} drained',
          timestamp: now,
          summary: 'No active streams detected.',
        ),
      );
    }
  }

  void _generateWorkerEvents(
    Map<String, WorkerStatus> previous,
    Map<String, WorkerStatus> current,
  ) {
    final remaining = Map<String, WorkerStatus>.from(previous);
    final now = stemNow().toUtc();
    for (final entry in current.entries) {
      final prev = remaining.remove(entry.key);
      final worker = entry.value;
      if (prev == null) {
        _recordEvent(
          DashboardEvent(
            title: 'Worker ${worker.workerId} online',
            timestamp: now,
            summary:
                'Heartbeat received with ${worker.queues.length} '
                'queue assignments.',
          ),
        );
        continue;
      }

      final inflightDelta = worker.inflight - prev.inflight;
      if (inflightDelta != 0) {
        _recordEvent(
          DashboardEvent(
            title:
                'Worker ${worker.workerId} inflight '
                '${_deltaLabel(inflightDelta)}',
            timestamp: now,
            summary:
                'Inflight changed from ${prev.inflight} to ${worker.inflight}.',
          ),
        );
      }
    }

    for (final worker in remaining.values) {
      _recordEvent(
        DashboardEvent(
          title: 'Worker ${worker.workerId} offline',
          timestamp: now,
          summary: 'Heartbeat stream ended for ${worker.workerId}.',
        ),
      );
    }
  }

  void _recordEvent(DashboardEvent event) {
    _events.insert(0, event);
    if (_events.length > eventLimit) {
      _events.removeRange(eventLimit, _events.length);
    }

    final fragment = renderEventItem(event);
    final payloads = <String>[
      turboStreamPrepend(target: 'event-log', html: fragment),
    ];
    if (_events.length == 1) {
      payloads.insert(0, turboStreamRemove(target: 'event-log-placeholder'));
    }
    hub.broadcast('stem-dashboard:events', payloads);
  }

  String _deltaLabel(int delta) {
    if (delta > 0) return 'increased by $delta';
    if (delta < 0) return 'decreased by ${delta.abs()}';
    return 'unchanged';
  }

  String _queueSignature(List<QueueSummary> queues) {
    final sorted = List<QueueSummary>.from(queues)
      ..sort((a, b) => a.queue.compareTo(b.queue));
    return sorted
        .map(
          (queue) {
            return '${queue.queue}:${queue.pending}:'
                '${queue.inflight}:${queue.deadLetters}';
          },
        )
        .join('|');
  }

  String _workerSignature(List<WorkerStatus> workers) {
    final sorted = List<WorkerStatus>.from(workers)
      ..sort((a, b) => a.workerId.compareTo(b.workerId));
    return sorted
        .map(
          (worker) {
            final stamp = worker.timestamp.toUtc().toIso8601String();
            return '${worker.workerId}:${worker.inflight}:$stamp';
          },
        )
        .join('|');
  }

  String _taskSignature(List<DashboardTaskStatusEntry> tasks) {
    return tasks
        .map(
          (task) {
            final stamp = task.updatedAt.toUtc().toIso8601String();
            return '${task.id}:${task.state.name}:${task.attempt}:$stamp';
          },
        )
        .join('|');
  }

  void _broadcastRefreshSignal() {
    final payload = turboStreamReplace(
      target: 'dashboard-refresh-signal',
      html: '<span>${stemNow().toUtc().toIso8601String()}</span>',
    );
    hub.broadcast('stem-dashboard:refresh', [payload]);
  }

  /// Records an audit entry.
  void recordAudit({
    required String kind,
    required String action,
    required String status,
    String? actor,
    String? summary,
    Map<String, Object?> metadata = const {},
  }) {
    final entry = DashboardAuditEntry(
      id: 'audit-${stemNow().toUtc().microsecondsSinceEpoch}',
      timestamp: stemNow().toUtc(),
      kind: kind,
      action: action,
      status: status,
      actor: actor,
      summary: summary,
      metadata: metadata,
    );
    _auditEntries.insert(0, entry);
    if (_auditEntries.length > auditLimit) {
      _auditEntries.removeRange(auditLimit, _auditEntries.length);
    }
    _broadcastRefreshSignal();
  }

  Future<void> _evaluateAlerts({
    required List<QueueSummary> queues,
    required List<WorkerStatus> workers,
    required List<DashboardTaskStatusEntry> tasks,
  }) async {
    final totalPending = queues.fold<int>(
      0,
      (total, queue) => total + queue.pending,
    );
    if (totalPending >= alertBacklogThreshold) {
      await _emitAlert(
        key: 'queue.backlog.high',
        summary: 'Backlog threshold exceeded: '
            '$totalPending >= $alertBacklogThreshold.',
        metadata: {
          'pendingTotal': totalPending,
          'threshold': alertBacklogThreshold,
        },
      );
    }

    final failedCount = tasks.where((task) {
      return task.state == TaskState.failed ||
          task.state == TaskState.cancelled;
    }).length;
    if (failedCount >= alertFailedTaskThreshold) {
      await _emitAlert(
        key: 'tasks.failed.high',
        summary: 'Failed task threshold exceeded: '
            '$failedCount >= $alertFailedTaskThreshold.',
        metadata: {
          'failedCount': failedCount,
          'threshold': alertFailedTaskThreshold,
        },
      );
    }

    final offlineWorkers = workers.where(
      (worker) => worker.age > const Duration(minutes: 2),
    );
    if (offlineWorkers.length >= alertOfflineWorkerThreshold) {
      await _emitAlert(
        key: 'workers.offline.high',
        summary:
            'Offline workers threshold exceeded: ${offlineWorkers.length} >= '
            '$alertOfflineWorkerThreshold.',
        metadata: {
          'offlineWorkers': offlineWorkers
              .map((worker) => worker.workerId)
              .toList(
                growable: false,
              ),
          'threshold': alertOfflineWorkerThreshold,
        },
      );
    }
  }

  Future<void> _emitAlert({
    required String key,
    required String summary,
    Map<String, Object?> metadata = const {},
  }) async {
    final now = stemNow().toUtc();
    final last = _lastAlertAt[key];
    if (last != null && now.difference(last) < alertCooldown) {
      return;
    }
    _lastAlertAt[key] = now;

    recordAudit(
      kind: 'alert',
      action: key,
      status: 'triggered',
      actor: 'system',
      summary: summary,
      metadata: metadata,
    );
    _recordEvent(
      DashboardEvent(
        title: 'Alert: $key',
        timestamp: now,
        summary: summary,
        metadata: metadata,
      ),
    );

    if (alertWebhookUrls.isEmpty) {
      recordAudit(
        kind: 'alert',
        action: key,
        status: 'skipped',
        actor: 'system',
        summary: 'No alert webhook URLs configured.',
      );
      return;
    }
    await _sendAlertWebhooks(key: key, summary: summary, metadata: metadata);
  }

  Future<void> _sendAlertWebhooks({
    required String key,
    required String summary,
    required Map<String, Object?> metadata,
  }) async {
    final payload = <String, Object?>{
      'kind': 'stem-dashboard-alert',
      'key': key,
      'summary': summary,
      'timestamp': stemNow().toUtc().toIso8601String(),
      'metadata': metadata,
    };

    for (final rawUrl in alertWebhookUrls) {
      final url = rawUrl.trim();
      if (url.isEmpty) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        recordAudit(
          kind: 'alert',
          action: key,
          status: 'error',
          actor: 'system',
          summary: 'Invalid webhook URL: $url',
        );
        continue;
      }

      HttpClientRequest? request;
      try {
        final client = HttpClient();
        request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(payload)));
        final response = await request.close();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          recordAudit(
            kind: 'alert',
            action: key,
            status: 'sent',
            actor: 'system',
            summary: 'Alert delivered to $url.',
          );
        } else {
          recordAudit(
            kind: 'alert',
            action: key,
            status: 'error',
            actor: 'system',
            summary: 'Webhook returned HTTP ${response.statusCode} for $url.',
          );
        }
        client.close(force: true);
      } on Object catch (error) {
        request?.abort();
        recordAudit(
          kind: 'alert',
          action: key,
          status: 'error',
          actor: 'system',
          summary: 'Webhook delivery failed for $url: $error',
        );
      }
    }
  }
}
