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

  /// Rehydrates a watcher from serialized JSON.
  factory WorkflowWatcher.fromJson(Map<String, Object?> json) {
    return WorkflowWatcher(
      runId: json['runId']?.toString() ?? '',
      stepName: json['stepName']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
      createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now().toUtc(),
      deadline: _dateFromJson(json['deadline']),
      data: (json['data'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

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

  /// Converts this watcher to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'stepName': stepName,
      'topic': topic,
      'createdAt': createdAt.toIso8601String(),
      if (deadline != null) 'deadline': deadline!.toIso8601String(),
      'data': data,
    };
  }
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

  /// Rehydrates a watcher resolution from serialized JSON.
  factory WorkflowWatcherResolution.fromJson(Map<String, Object?> json) {
    return WorkflowWatcherResolution(
      runId: json['runId']?.toString() ?? '',
      stepName: json['stepName']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
      resumeData:
          (json['resumeData'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// Run identifier that was resumed.
  final String runId;

  /// Step name that registered the watcher.
  final String stepName;

  /// Topic that resolved the watcher.
  final String topic;

  /// Resume data merged from stored metadata and event payload.
  final Map<String, Object?> resumeData;

  /// Converts this resolution to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'stepName': stepName,
      'topic': topic,
      'resumeData': resumeData,
    };
  }
}

DateTime? _dateFromJson(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
