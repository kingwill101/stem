/// Describes a workflow event watcher registered by the runtime.
class WorkflowWatcher {
  WorkflowWatcher({
    required this.runId,
    required this.stepName,
    required this.topic,
    required this.createdAt,
    this.deadline,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(Map<String, Object?>.from(data));

  /// Identifier of the workflow run waiting on the event.
  final String runId;

  /// Name of the step that registered the watcher.
  final String stepName;

  /// Event topic that will resume the run.
  final String topic;

  /// Timestamp when the watcher was registered.
  final DateTime createdAt;

  /// Optional deadline after which the watcher should time out.
  final DateTime? deadline;

  /// Additional metadata supplied when the watcher was registered.
  final Map<String, Object?> data;
}

/// Represents a watcher that has been resolved (event delivered or timed out).
class WorkflowWatcherResolution {
  WorkflowWatcherResolution({
    required this.runId,
    required this.stepName,
    required this.topic,
    required Map<String, Object?> resumeData,
  }) : resumeData = Map.unmodifiable(Map<String, Object?>.from(resumeData));

  final String runId;
  final String stepName;
  final String topic;
  final Map<String, Object?> resumeData;
}
