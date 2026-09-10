import 'dart:async';

import 'package:stem/stem.dart';

import 'demo_tasks.dart';

/// Bounded, reproducible workloads; tests can inject a much smaller preset.
class PhotoWorkload {
  const PhotoWorkload({
    required this.label,
    required this.count,
    required this.width,
    required this.height,
  }) : assert(count > 0 && count <= 12),
       assert(width >= 64 && width <= 2048),
       assert(height >= 64 && height <= 1536);

  static const single = PhotoWorkload(
    label: 'Single photo',
    count: 1,
    width: 960,
    height: 640,
  );
  static const quick = PhotoWorkload(
    label: 'Quick',
    count: 3,
    width: 960,
    height: 640,
  );
  static const standard = PhotoWorkload(
    label: 'Standard',
    count: 6,
    width: 1600,
    height: 1000,
  );
  static const heavy = PhotoWorkload(
    label: 'Heavy',
    count: 12,
    width: 2048,
    height: 1536,
  );
  static const presets = [quick, standard, heavy];

  final String label;
  final int count;
  final int width;
  final int height;
}

bool isPhotoPending(TaskState state) =>
    state == TaskState.queued ||
    state == TaskState.running ||
    state == TaskState.retried;

/// Root-owned publication. Shutdown joins the current commit and wakeup, but
/// does not start another photo after the screen has gone away.
class PhotoBatchProducer {
  PhotoBatchProducer(
    this.app, {
    required this.outputDirectory,
    this.requestWakeup,
    this.onCommitted,
  });

  final StemApp app;
  final String outputDirectory;
  final Future<void> Function()? requestWakeup;
  final Future<void> Function(StemApp)? onCommitted;
  Future<String>? _publishing;
  bool _stopped = false;
  int _sequence = 0;

  Future<String> publish(PhotoWorkload workload) {
    if (_stopped) return Future.value('Photo Lab is closed.');
    return _publishing ??= _publish(workload).whenComplete(() {
      _publishing = null;
    });
  }

  Future<String> _publish(PhotoWorkload workload) async {
    // Enforce the per-request bounds in release builds too.
    if (workload.count < 1 ||
        workload.count > 12 ||
        workload.width < 64 ||
        workload.width > 2048 ||
        workload.height < 64 ||
        workload.height > 1536) {
      return 'Choose 1–12 photos, 64–2048 pixels wide and '
          '64–1536 pixels high.';
    }
    final batchId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    var committed = 0;
    Object? failure;
    try {
      // Each explicit request adds independent work to the existing runner.
      for (var index = 0; index < workload.count && !_stopped; index++) {
        await app.enqueueCall(
          preparePhoto.buildCall(
            PhotoTaskArgs(
              outputDirectory: outputDirectory,
              batchId: batchId,
              index: index,
              width: workload.width,
              height: workload.height,
            ),
            meta: {
              'batchId': batchId,
              'batchSize': workload.count,
              'label': workload.label,
              'index': index,
              'width': workload.width,
              'height': workload.height,
            },
          ),
        );
        committed++;
      }
    } catch (error) {
      failure = error;
    }
    var message = '$committed of ${workload.count} photos committed.';
    if (failure != null) {
      message += ' Publication stopped: $failure. Refresh before retrying.';
    }
    if (committed > 0 && onCommitted != null) {
      // Optional status surfaces cannot turn successful publication into
      // failure or prevent scheduling the already durable work.
      try {
        await onCommitted!(app);
      } catch (_) {}
    }
    // A partial batch is still real work. Scheduling retries never republish.
    if (committed > 0 && requestWakeup != null) {
      try {
        await requestWakeup!();
        message += ' Wakeup requested; Android decides when work runs.';
      } catch (error) {
        message +=
            ' Work is queued, but wakeup failed: $error. '
            'Use Retry wakeup; do not publish again.';
      }
    }
    return message;
  }

  void stopPublishing() => _stopped = true;

  Future<void> dispose() async {
    stopPublishing();
    await _publishing;
  }
}

/// Whole-photo progress reconstructed exclusively from persisted records.
class PhotoBatchSummary {
  PhotoBatchSummary(this.id, this.jobs);
  final String id;
  final List<TaskStatusRecord> jobs;
  DateTime get createdAt =>
      jobs.map((job) => job.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
  bool get hasPending => jobs.any((job) => isPhotoPending(job.status.state));
  String get label => jobs.first.status.meta['label']?.toString() ?? 'Photos';
  int get planned =>
      (jobs.first.status.meta['batchSize'] as num?)?.toInt() ?? jobs.length;
  int get succeeded =>
      jobs.where((job) => job.status.state == TaskState.succeeded).length;
  int get failed => jobs
      .where(
        (job) =>
            job.status.state == TaskState.failed ||
            job.status.state == TaskState.cancelled,
      )
      .length;
  int get running =>
      jobs.where((job) => job.status.state == TaskState.running).length;
  int get queued => jobs.length - succeeded - failed - running;
  int get completed => succeeded + failed;
  double get fraction => planned == 0 ? 0 : completed / planned;
  int metric(String key) => jobs.fold(0, (sum, job) {
    final payload = job.status.payload;
    final value = payload is Map ? payload[key] : null;
    return sum + (value is num ? value.toInt() : 0);
  });

  /// Prefer unfinished work; otherwise keep the latest batch's final result.
  ///
  /// Creation time, not status update time or backend iteration order, defines
  /// recency. Batch IDs break timestamp ties deterministically.
  static PhotoBatchSummary? activeOrLatest(List<TaskStatusRecord> jobs) {
    final batches = fromJobs(jobs);
    batches.sort((a, b) {
      if (a.hasPending != b.hasPending) return a.hasPending ? -1 : 1;
      final byCreation = b.createdAt.compareTo(a.createdAt);
      return byCreation != 0 ? byCreation : b.id.compareTo(a.id);
    });
    return batches.isEmpty ? null : batches.first;
  }

  static List<PhotoBatchSummary> fromJobs(List<TaskStatusRecord> jobs) {
    final groups = <String, List<TaskStatusRecord>>{};
    for (final job in jobs) {
      final id = job.status.meta['batchId'];
      if (id is String) (groups[id] ??= []).add(job);
    }
    return groups.entries
        .map((entry) => PhotoBatchSummary(entry.key, entry.value))
        .toList();
  }
}
