import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_flutter/src/monitor/stem_flutter_queue_snapshot.dart';
import 'package:stem_flutter/src/runtime/stem_flutter_worker_signal.dart';

/// Polls queue state and merges worker signals into UI snapshots.
class StemFlutterQueueMonitor {
  /// Creates a queue monitor for a single Stem queue.
  StemFlutterQueueMonitor({
    required ResultBackend backend,
    required Broker broker,
    required String queueName,
    required String workerId,
    Duration pollInterval = const Duration(seconds: 1),
    Duration heartbeatInterval = const Duration(seconds: 2),
    int limit = 40,
    String Function(TaskStatus status)? labelResolver,
  }) : _backend = backend,
       _broker = broker,
       _queueName = queueName,
       _workerId = workerId,
       _pollInterval = pollInterval,
       _heartbeatFreshness = heartbeatInterval * 3,
       _limit = limit,
       _labelResolver =
           labelResolver ??
           ((status) => status.meta['label']?.toString() ?? status.id);

  final ResultBackend _backend;
  final Broker _broker;
  final String _queueName;
  final String _workerId;
  final Duration _pollInterval;
  final Duration _heartbeatFreshness;
  final int _limit;
  final String Function(TaskStatus status) _labelResolver;

  final StreamController<StemFlutterQueueSnapshot> _controller =
      StreamController<StemFlutterQueueSnapshot>.broadcast();

  Timer? _timer;
  StreamSubscription<StemFlutterWorkerSignal>? _workerSignalsSub;
  StemFlutterQueueSnapshot _snapshot = const StemFlutterQueueSnapshot();
  bool _refreshInFlight = false;
  bool _started = false;

  /// The most recently emitted queue snapshot.
  StemFlutterQueueSnapshot get snapshot => _snapshot;

  /// A broadcast stream of queue snapshots.
  Stream<StemFlutterQueueSnapshot> get snapshots => _controller.stream;

  /// Starts periodic polling for this queue.
  ///
  /// This method performs an immediate [refresh] before scheduling the periodic
  /// timer. Calling it more than once has no effect.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
  }

  /// Binds worker signals emitted by a supervised worker isolate.
  ///
  /// When multiple signal streams are bound over time, the previous
  /// subscription is replaced.
  void bindWorkerSignals(Stream<StemFlutterWorkerSignal> signals) {
    unawaited(_workerSignalsSub?.cancel());
    _workerSignalsSub = signals.listen(_applyWorkerSignal);
  }

  /// Forces an immediate refresh of queue and heartbeat state.
  Future<void> refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final page = await _backend.listTaskStatuses(
        TaskStatusListRequest(queue: _queueName, limit: _limit),
      );
      final heartbeats = await _backend.listWorkerHeartbeats();
      final pendingCount = await _broker.pendingCount(_queueName);
      final inflightCount = await _broker.inflightCount(_queueName);

      final jobs =
          page.items
              .map((record) {
                final status = record.status;
                return StemFlutterTrackedJob(
                  taskId: status.id,
                  label: _labelResolver(status),
                  state: status.state,
                  result: status.payloadValue<String>(),
                  errorMessage: status.error?.message,
                  updatedAt: record.updatedAt.toUtc(),
                );
              })
              .toList(growable: false)
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

      final latestHeartbeat = heartbeats
          .where((heartbeat) => heartbeat.workerId == _workerId)
          .fold<WorkerHeartbeat?>(
            null,
            (current, heartbeat) =>
                current == null ||
                    heartbeat.timestamp.isAfter(current.timestamp)
                ? heartbeat
                : current,
          );
      final latestHeartbeatAt = latestHeartbeat?.timestamp.toUtc();
      final hasFreshHeartbeat =
          latestHeartbeatAt != null &&
          DateTime.now().toUtc().difference(latestHeartbeatAt) <=
              _heartbeatFreshness;

      var next = _snapshot.copyWith(
        jobs: jobs,
        lastHeartbeatAt: latestHeartbeatAt,
        pendingCount: pendingCount,
        inflightCount: inflightCount,
      );

      if (next.workerStatus != StemFlutterWorkerStatus.error &&
          next.workerStatus != StemFlutterWorkerStatus.stopped) {
        if (hasFreshHeartbeat) {
          next = next.copyWith(
            workerStatus: StemFlutterWorkerStatus.running,
            workerDetail: 'Heartbeat ${_formatTimestamp(latestHeartbeatAt)}',
          );
        } else if (latestHeartbeatAt != null) {
          next = next.copyWith(
            workerStatus: StemFlutterWorkerStatus.waiting,
            workerDetail:
                'Last heartbeat ${_formatTimestamp(latestHeartbeatAt)}',
          );
        }
      }

      _emit(next);
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Stops polling and releases this monitor's subscriptions.
  Future<void> dispose() async {
    _timer?.cancel();
    await _workerSignalsSub?.cancel();
    await _controller.close();
  }

  void _applyWorkerSignal(StemFlutterWorkerSignal signal) {
    final next = switch (signal.type) {
      StemFlutterWorkerSignalType.ready => _snapshot.copyWith(
        workerStatus: StemFlutterWorkerStatus.running,
        workerDetail: signal.detail ?? 'Worker isolate ready.',
      ),
      StemFlutterWorkerSignalType.status => _snapshot.copyWith(
        workerStatus: signal.status,
        workerDetail: signal.detail,
        clearWorkerDetail: signal.detail == null,
      ),
      StemFlutterWorkerSignalType.warning => _snapshot,
      StemFlutterWorkerSignalType.fatal => _snapshot.copyWith(
        workerStatus: StemFlutterWorkerStatus.error,
        workerDetail: signal.message,
      ),
    };
    if (!identical(next, _snapshot)) {
      _emit(next);
    }
  }

  void _emit(StemFlutterQueueSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }
}

String _formatTimestamp(DateTime? value) {
  if (value == null) return 'none';
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.hour)}:'
      '${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}';
}
