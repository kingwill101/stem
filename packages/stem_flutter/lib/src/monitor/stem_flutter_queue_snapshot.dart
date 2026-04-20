import 'package:stem/stem.dart';
import 'package:stem_flutter/src/runtime/stem_flutter_worker_signal.dart';

/// UI-friendly representation of a tracked task.
///
/// Instances of this type are intended for display and are derived from
/// backend status records.
class StemFlutterTrackedJob {
  /// Creates a tracked job.
  const StemFlutterTrackedJob({
    required this.taskId,
    required this.label,
    required this.state,
    required this.updatedAt,
    this.result,
    this.errorMessage,
  });

  /// Task identifier.
  final String taskId;

  /// Human-readable label.
  final String label;

  /// Current task state.
  final TaskState state;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Decoded string result, when available.
  final String? result;

  /// Error message, when available.
  final String? errorMessage;
}

/// Aggregate queue and worker state exposed to Flutter UIs.
///
/// This snapshot is intentionally compact so widgets can render queue depth,
/// worker health, and recent jobs without depending on backend-specific types.
class StemFlutterQueueSnapshot {
  /// Creates a queue snapshot.
  const StemFlutterQueueSnapshot({
    this.workerStatus = StemFlutterWorkerStatus.starting,
    this.workerDetail,
    this.lastHeartbeatAt,
    this.pendingCount,
    this.inflightCount,
    this.jobs = const <StemFlutterTrackedJob>[],
  });

  /// Current worker state.
  final StemFlutterWorkerStatus workerStatus;

  /// Detail text attached to the current worker state.
  final String? workerDetail;

  /// Most recent worker heartbeat timestamp.
  final DateTime? lastHeartbeatAt;

  /// Number of broker-visible pending items.
  final int? pendingCount;

  /// Number of broker-visible inflight items.
  final int? inflightCount;

  /// Most recent tracked jobs from the result backend.
  final List<StemFlutterTrackedJob> jobs;

  /// Returns a copy with selected fields replaced.
  StemFlutterQueueSnapshot copyWith({
    StemFlutterWorkerStatus? workerStatus,
    String? workerDetail,
    bool clearWorkerDetail = false,
    DateTime? lastHeartbeatAt,
    int? pendingCount,
    int? inflightCount,
    List<StemFlutterTrackedJob>? jobs,
  }) {
    return StemFlutterQueueSnapshot(
      workerStatus: workerStatus ?? this.workerStatus,
      workerDetail: clearWorkerDetail
          ? null
          : workerDetail ?? this.workerDetail,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      pendingCount: pendingCount ?? this.pendingCount,
      inflightCount: inflightCount ?? this.inflightCount,
      jobs: jobs ?? this.jobs,
    );
  }

  /// A short detail line suitable for compact UI headers.
  String? get workerDetailPreview {
    final detail = workerDetail?.trim();
    if (detail == null || detail.isEmpty) return null;
    return detail.split('\n').first.trim();
  }
}
