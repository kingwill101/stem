import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stem/stem.dart';

import 'photo_batch.dart';

/// Example-only dashboard reads; the application owner still owns the stores.
class QueueDebugController with WidgetsBindingObserver {
  QueueDebugController(
    this.app, {
    required this.queueName,
    this.reconciliationInterval = const Duration(seconds: 1),
  }) : assert(reconciliationInterval > Duration.zero);

  final StemApp app;
  final String queueName;
  final Duration reconciliationInterval;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<WorkerEvent>? _events;
  Future<void>? _reading;
  Future<void>? _closing;
  bool _requested = false;
  bool _disposed = false;
  bool _started = false;
  bool _visible = true;
  bool _pageVisible = true;
  Timer? _timer;

  bool get _canObserve => _visible && _pageVisible;

  bool get hasUnfinishedWork =>
      (pendingCount ?? 0) > 0 ||
      (inflightCount ?? 0) > 0 ||
      jobs.any((job) => isPhotoPending(job.status.state));

  void setVisible(bool visible) {
    if (_disposed) return;
    _visible = visible;
    _updateVisibility();
  }

  /// Page selection is independent of the application's foreground lifecycle.
  void setPageVisible(bool visible) {
    if (_disposed) return;
    _pageVisible = visible;
    _updateVisibility();
  }

  void _updateVisibility() {
    _timer?.cancel();
    _timer = null;
    if (_canObserve) unawaited(refresh());
  }

  void _scheduleReconciliation() {
    _timer?.cancel();
    _timer = null;
    if (!_disposed &&
        _started &&
        _canObserve &&
        (hasUnfinishedWork || observationError != null)) {
      _timer = Timer(reconciliationInterval, () {
        _timer = null;
        unawaited(refresh());
      });
    }
  }

  Stream<void> get changes => _changes.stream;
  List<TaskStatusRecord> jobs = const [];
  int? pendingCount;
  int? inflightCount;
  DateTime? updatedAt;
  Object? observationError;
  bool get isRunning => app.isStarted;

  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _events = app.worker.events.listen((_) {
      if (_canObserve) unawaited(refresh());
    });
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setVisible(state == AppLifecycleState.resumed);
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _requested = true;
    return _reading ??= _read().whenComplete(() {
      _reading = null;
      // A stream listener can request a refresh after the loop exits but
      // before its future completes.
      if (_requested && !_disposed) return refresh();
      _scheduleReconciliation();
    });
  }

  Future<void> _read() async {
    // An event during any await requests another pass, including completion
    // events arriving after a read captured an older running status.
    while (_requested && !_disposed) {
      _requested = false;
      try {
        final records = <TaskStatusRecord>[];
        int? offset = 0;
        do {
          final page = await app.backend.listTaskStatuses(
            TaskStatusListRequest(queue: queueName, offset: offset!),
          );
          records.addAll(page.items);
          offset = page.nextOffset;
          if (_disposed) return;
        } while (offset != null);
        final pending = await app.broker.pendingCount(queueName);
        final inflight = await app.broker.inflightCount(queueName);
        if (_disposed) return;
        jobs = records;
        pendingCount = pending;
        inflightCount = inflight;
        updatedAt = DateTime.now();
        observationError = null;
      } catch (error) {
        if (_disposed) return;
        observationError = error;
      }
      _changes.add(null);
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    await _events?.cancel();
    await _reading;
    await _changes.close();
  }
}
