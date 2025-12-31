import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

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
  }) : hub = TurboStreamHub();

  /// Data source used to fetch queues and workers.
  final DashboardDataSource service;

  /// Turbo stream hub used to broadcast events.
  final TurboStreamHub hub;

  /// Polling interval used to refresh state.
  final Duration pollInterval;

  /// Maximum number of events retained in memory.
  final int eventLimit;

  Timer? _timer;
  List<QueueSummary> _previousQueues = const [];
  Map<String, WorkerStatus> _previousWorkers = const {};
  final _events = <DashboardEvent>[];
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
    final queues = await service.fetchQueueSummaries();
    final workers = await service.fetchWorkerStatuses();
    _updateThroughput(queues);

    _generateQueueEvents(_previousQueues, queues);
    _generateWorkerEvents(_previousWorkers, {
      for (final worker in workers) worker.workerId: worker,
    });

    _previousQueues = queues;
    _previousWorkers = {for (final worker in workers) worker.workerId: worker};
  }

  void _updateThroughput(List<QueueSummary> queues) {
    final now = DateTime.now().toUtc();
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
    final now = DateTime.now().toUtc();
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
    final now = DateTime.now().toUtc();
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
}
