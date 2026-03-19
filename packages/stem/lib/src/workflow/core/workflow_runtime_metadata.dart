import 'dart:collection';

/// Reserved params key storing internal runtime metadata for workflow runs.
const String workflowRuntimeMetadataParamKey = '__stem.workflow.runtime';

/// Logical channel used by workflow-related task enqueues.
enum WorkflowChannelKind {
  /// Orchestration channel used by workflow continuation tasks.
  orchestration,

  /// Execution channel used by step-spawned task work.
  execution,
}

/// Why a workflow continuation task was enqueued.
enum WorkflowContinuationReason {
  /// Initial run dispatch from `startWorkflow`.
  start,

  /// Run resumed because a timer/sleep became due.
  due,

  /// Run resumed because an awaited external event was delivered.
  event,

  /// Run was re-enqueued manually.
  manual,

  /// Run was re-enqueued as part of replay/rewind operations.
  replay,
}

/// Run-scoped runtime metadata persisted alongside workflow params.
class WorkflowRunRuntimeMetadata {
  /// Creates immutable runtime metadata.
  const WorkflowRunRuntimeMetadata({
    required this.workflowId,
    required this.orchestrationQueue,
    required this.continuationQueue,
    required this.executionQueue,
    this.serializationFormat = 'json',
    this.serializationVersion = '1',
    this.frameFormat = 'json-frame',
    this.frameVersion = '1',
    this.encryptionScope = 'none',
    this.encryptionEnabled = false,
    this.streamId,
  });

  /// Restores metadata from a JSON map.
  factory WorkflowRunRuntimeMetadata.fromJson(Map<String, Object?> json) {
    return WorkflowRunRuntimeMetadata(
      workflowId: json['workflowId']?.toString() ?? '',
      orchestrationQueue:
          json['orchestrationQueue']?.toString().trim().isNotEmpty == true
          ? json['orchestrationQueue']!.toString().trim()
          : 'workflow',
      continuationQueue:
          json['continuationQueue']?.toString().trim().isNotEmpty == true
          ? json['continuationQueue']!.toString().trim()
          : 'workflow',
      executionQueue:
          json['executionQueue']?.toString().trim().isNotEmpty == true
          ? json['executionQueue']!.toString().trim()
          : 'default',
      serializationFormat:
          json['serializationFormat']?.toString().trim().isNotEmpty == true
          ? json['serializationFormat']!.toString().trim()
          : 'json',
      serializationVersion:
          json['serializationVersion']?.toString().trim().isNotEmpty == true
          ? json['serializationVersion']!.toString().trim()
          : '1',
      frameFormat: json['frameFormat']?.toString().trim().isNotEmpty == true
          ? json['frameFormat']!.toString().trim()
          : 'json-frame',
      frameVersion: json['frameVersion']?.toString().trim().isNotEmpty == true
          ? json['frameVersion']!.toString().trim()
          : '1',
      encryptionScope:
          json['encryptionScope']?.toString().trim().isNotEmpty == true
          ? json['encryptionScope']!.toString().trim()
          : 'none',
      encryptionEnabled: json['encryptionEnabled'] == true,
      streamId: json['streamId']?.toString(),
    );
  }

  /// Extracts metadata from [params], defaulting when absent.
  factory WorkflowRunRuntimeMetadata.fromParams(Map<String, Object?> params) {
    final raw = params[workflowRuntimeMetadataParamKey];
    if (raw is Map) {
      return WorkflowRunRuntimeMetadata.fromJson(raw.cast<String, Object?>());
    }
    return const WorkflowRunRuntimeMetadata(
      workflowId: '',
      orchestrationQueue: 'workflow',
      continuationQueue: 'workflow',
      executionQueue: 'default',
    );
  }

  /// Stable identifier for the workflow definition.
  final String workflowId;

  /// Queue used for initial orchestration tasks.
  final String orchestrationQueue;

  /// Queue used for continuation orchestration tasks.
  final String continuationQueue;

  /// Default queue used for execution channel tasks.
  final String executionQueue;

  /// Serialization format label for run-scoped payload framing.
  final String serializationFormat;

  /// Serialization schema/version identifier.
  final String serializationVersion;

  /// Stream frame format identifier.
  final String frameFormat;

  /// Stream frame version identifier.
  final String frameVersion;

  /// Encryption scope identifier.
  final String encryptionScope;

  /// Whether run payloads are expected to be encrypted.
  final bool encryptionEnabled;

  /// Stable stream identifier for per-run framing.
  final String? streamId;

  /// Converts metadata to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'workflowId': workflowId,
      'orchestrationQueue': orchestrationQueue,
      'continuationQueue': continuationQueue,
      'executionQueue': executionQueue,
      'serializationFormat': serializationFormat,
      'serializationVersion': serializationVersion,
      'frameFormat': frameFormat,
      'frameVersion': frameVersion,
      'encryptionScope': encryptionScope,
      'encryptionEnabled': encryptionEnabled,
      if (streamId != null && streamId!.isNotEmpty) 'streamId': streamId,
    };
  }

  /// Returns a new params map containing this metadata under the reserved key.
  Map<String, Object?> attachToParams(Map<String, Object?> params) {
    return Map<String, Object?>.unmodifiable({
      ...params,
      workflowRuntimeMetadataParamKey: toJson(),
    });
  }

  /// Returns params without internal runtime metadata.
  static Map<String, Object?> stripFromParams(Map<String, Object?> params) {
    if (!params.containsKey(workflowRuntimeMetadataParamKey)) {
      return Map<String, Object?>.unmodifiable(params);
    }
    final copy = Map<String, Object?>.from(params)
      ..remove(workflowRuntimeMetadataParamKey);
    return UnmodifiableMapView(copy);
  }
}
