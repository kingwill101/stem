/// Describes a workflow event watcher registered by the runtime.
class WorkflowWatcher {
  /// Creates a watcher entry for a suspended workflow run.
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
  /// Creates a resolution payload for a resumed watcher.
  WorkflowWatcherResolution({
    required this.runId,
    required this.stepName,
    required this.topic,
    required Map<String, Object?> resumeData,
  }) : resumeData = Map.unmodifiable(Map<String, Object?>.from(resumeData));

  /// Run identifier that was resumed.
  final String runId;

  /// Step name that registered the watcher.
  final String stepName;

  /// Topic that resolved the watcher.
  final String topic;

  /// Resume data merged from stored metadata and event payload.
  final Map<String, Object?> resumeData;
}
