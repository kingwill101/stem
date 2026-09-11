import 'dart:async';

import 'package:stem/stem.dart';

import 'demo_workers.dart';
import 'routing_tasks.dart';

/// App-owned durable commands and observations; never starts or controls workers.
///
/// The owner must await [dispose] before closing the apps and their storage.
class WorkerWorkbenchController {
  WorkerWorkbenchController(
    this.app, {
    List<StemApp> localApps = const [],
    this.requestWakeup,
  }) : localApps = List.unmodifiable(localApps);

  final StemApp app;
  final List<StemApp> localApps;
  final Future<void> Function()? requestWakeup;
  final _changes = StreamController<void>.broadcast();
  Future<void> _pending = Future<void>.value();
  Future<void>? _refreshing;
  Future<void>? _closing;
  Timer? _timer;
  bool _disposed = false;
  bool _visible = false;

  Stream<void> get changes => _changes.stream;
  List<TaskStatusRecord> records = const [];
  Object? observationError;
  DateTime? updatedAt;

  /// In-process snapshots only, not evidence of headless worker health.
  Map<String, bool> get localStarted => {
    for (final local in localApps) local.worker.workerId: local.isStarted,
  };

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) return Future<T>.error(StateError('Workbench is disposed'));
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<String>> enqueue(String queue, {int count = 6}) => _enqueue(
    () async {
      if (!demoWorkerSpecs.any((spec) => spec.queues.contains(queue))) {
        throw ArgumentError.value(queue, 'queue', 'Unknown demo queue');
      }
      if (count < 1 || count > 6) {
        throw RangeError.range(count, 1, 6, 'count');
      }
      var savedWork = false;
      try {
        final ids = await enqueueRoutingProbes(app, queue: queue, count: count);
        savedWork = ids.isNotEmpty;
        return ids;
      } on RoutingProbePublicationFailure catch (error) {
        savedWork = error.committedIds.isNotEmpty;
        Error.throwWithStackTrace(error.cause, error.stackTrace);
      } finally {
        try {
          // A partial batch is durable work too; never republish it to wake it.
          if (savedWork) await requestWakeup?.call();
        } finally {
          await _read();
        }
      }
    },
  );

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _refreshing ??= _enqueue(_read).whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _read() async {
    try {
      final next = <TaskStatusRecord>[];
      int? offset = 0;
      while (offset != null) {
        final page = await app.backend.listTaskStatuses(
          TaskStatusListRequest(
            meta: const {'probeBatchId': null},
            limit: 100,
            offset: offset,
          ),
        );
        next.addAll(
          page.items.where((item) => item.status.meta['probeBatchId'] != null),
        );
        offset = page.nextOffset;
      }
      next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      records = List.unmodifiable(next);
      updatedAt = DateTime.now();
      observationError = null;
    } catch (error) {
      observationError = error;
    }
    if (!_disposed) {
      _changes.add(null);
      _scheduleRefresh();
    }
  }

  void setVisible(bool visible) {
    if (_disposed) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (visible) unawaited(refresh());
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    _timer = null;
    if (_visible && !_disposed) {
      _timer = Timer(const Duration(seconds: 1), () {
        _timer = null;
        unawaited(refresh());
      });
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _pending;
    await _changes.close();
  }
}
