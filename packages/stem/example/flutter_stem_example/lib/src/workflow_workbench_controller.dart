import 'dart:async';

import 'package:stem/stem.dart';

import 'demo_workflows.dart';

/// Example-only observations and durable commands; never starts a worker.
///
/// The owner must await [dispose] before closing workflow/core storage.
class WorkflowWorkbenchController {
  WorkflowWorkbenchController(this.workflows, {this.requestWakeup});

  final StemWorkflowApp workflows;
  final Future<void> Function()? requestWakeup;
  final _changes = StreamController<void>.broadcast();
  Future<void> _pending = Future<void>.value();
  Future<void>? _refreshing;
  Future<void>? _closing;
  Timer? _timer;
  bool _disposed = false;
  bool _visible = true;

  Stream<void> get changes => _changes.stream;
  List<WorkflowRunView> runs = const [];
  Map<String, WorkflowRunDetailView> details = const {};
  Object? observationError;
  DateTime? updatedAt;
  static const historyPageSize = 20;
  WorkbenchWorkflowKind historyWorkflow = WorkbenchWorkflowKind.report;
  WorkflowStatus? historyStatus;
  int historyPage = 0;
  bool hasNextPage = false;

  Future<void> selectHistory({
    required WorkbenchWorkflowKind workflow,
    WorkflowStatus? status,
  }) => _enqueue(() async {
    historyWorkflow = workflow;
    historyStatus = status;
    historyPage = 0;
    runs = const [];
    details = const {};
    hasNextPage = false;
    await _read();
  });

  Future<void> nextPage() => _enqueue(() async {
    if (!hasNextPage) return;
    historyPage++;
    runs = const [];
    details = const {};
    hasNextPage = false;
    await _read();
  });

  Future<void> previousPage() => _enqueue(() async {
    if (historyPage == 0) return;
    historyPage--;
    runs = const [];
    details = const {};
    hasNextPage = false;
    await _read();
  });

  /// Checkpoints are read only on demand, never by the polling loop.
  Future<void> loadDetail(String runId) => _enqueue(() async {
    if (!runs.any((run) => run.runId == runId)) return;
    final detail = await workflows.viewRunDetail(runId);
    details = Map.unmodifiable({
      for (final entry in details.entries)
        if (entry.key != runId) entry.key: entry.value,
      runId: ?detail,
    });
    if (!_disposed) _changes.add(null);
  });

  // A single queue makes disposal join both reads and mutations and prevents
  // older reads from overwriting observations made after a durable command.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) return Future<T>.error(StateError('Workbench is disposed'));
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<String>> launch(
    WorkbenchWorkflowKind kind, {
    int count = 1,
  }) => _enqueue(() async {
    if (count < 1 || count > 5) {
      throw RangeError.range(count, 1, 5, 'count');
    }
    final ids = <String>[];
    try {
      for (var index = 0; index < count; index++) {
        // Unlike the app facade, this does not implicitly start runtime polling.
        ids.add(await workflows.runtime.startWorkflow(kind.descriptor.name));
      }
      return ids;
    } finally {
      try {
        if (ids.isNotEmpty) await requestWakeup?.call();
      } finally {
        historyWorkflow = kind;
        historyStatus = null;
        historyPage = 0;
        runs = const [];
        details = const {};
        hasNextPage = false;
        await _read();
      }
    }
  });

  Future<void> approve(String runId) => _enqueue(() async {
    final run = await workflows.store.get(runId);
    final topic = workflowApprovalTopic(runId);
    if (run == null ||
        run.workflow != WorkbenchWorkflowKind.approval.descriptor.name ||
        run.status != WorkflowStatus.suspended ||
        run.waitTopic != topic) {
      throw StateError('Run $runId is not waiting for approval');
    }
    await workflows.runtime.emit(topic, {'approved': true, 'runId': runId});
    try {
      await requestWakeup?.call();
    } finally {
      await _read();
    }
  });

  Future<void> cancel(String runId) => _enqueue(() async {
    final run = await workflows.store.get(runId);
    if (run == null ||
        !demoWorkflowDescriptors.any((item) => item.name == run.workflow)) {
      throw StateError('Unknown demo workflow run $runId');
    }
    if (run.status == WorkflowStatus.completed ||
        run.status == WorkflowStatus.failed ||
        run.status == WorkflowStatus.cancelled) {
      throw StateError('Run $runId has already finished');
    }
    await workflows.runtime.cancelWorkflow(runId);
    // Cancelling a run must not resume a user-paused native scheduler or start
    // unrelated work. Existing envelopes can be settled on a later wakeup.
    await _read();
  });

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _refreshing ??= _enqueue(_read).whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _read() async {
    try {
      final page = await workflows.listRunViews(
        workflow: historyWorkflow.descriptor.name,
        status: historyStatus,
        limit: historyPageSize + 1,
        offset: historyPage * historyPageSize,
      );
      final next = page.take(historyPageSize).toList();
      // Retain only unchanged details on this page. A changed run must be
      // explicitly expanded/reloaded; polling never reads checkpoints.
      final previous = {for (final run in runs) run.runId: run};
      details = Map.unmodifiable({
        for (final run in next)
          if (details.containsKey(run.runId) &&
              previous[run.runId]?.updatedAt == run.updatedAt &&
              previous[run.runId]?.status == run.status &&
              previous[run.runId]?.cursor == run.cursor)
            run.runId: details[run.runId]!,
      });
      runs = List.unmodifiable(next);
      hasNextPage = page.length > historyPageSize;
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
