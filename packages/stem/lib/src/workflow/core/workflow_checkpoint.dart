import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_step.dart';

/// Declared script checkpoint metadata used for tooling and replay boundaries.
///
/// Unlike [FlowStep], a [WorkflowCheckpoint] does not define execution logic.
/// Script workflows execute their `run(...)` body directly and use these
/// declarations only for manifests, introspection, encoding, and replay
/// metadata.
class WorkflowCheckpoint {
  /// Creates declared checkpoint metadata for a script workflow.
  WorkflowCheckpoint({
    required this.name,
    this.autoVersion = false,
    String? title,
    Object? Function(Object? value)? valueEncoder,
    Object? Function(Object? payload)? valueDecoder,
    this.kind = WorkflowStepKind.task,
    Iterable<String> taskNames = const [],
    Map<String, Object?>? metadata,
  }) : title = title ?? name,
       _valueEncoder = valueEncoder,
       _valueDecoder = valueDecoder,
       taskNames = List.unmodifiable(taskNames),
       metadata = metadata == null ? null : Map.unmodifiable(metadata);

  /// Creates checkpoint metadata backed by a typed [valueCodec].
  static WorkflowCheckpoint typed<T>({
    required String name,
    required PayloadCodec<T> valueCodec,
    bool autoVersion = false,
    String? title,
    WorkflowStepKind kind = WorkflowStepKind.task,
    Iterable<String> taskNames = const [],
    Map<String, Object?>? metadata,
  }) {
    return WorkflowCheckpoint(
      name: name,
      autoVersion: autoVersion,
      title: title,
      valueEncoder: valueCodec.encodeDynamic,
      valueDecoder: valueCodec.decodeDynamic,
      kind: kind,
      taskNames: taskNames,
      metadata: metadata,
    );
  }

  /// Rehydrates declared checkpoint metadata from serialized JSON.
  factory WorkflowCheckpoint.fromJson(Map<String, Object?> json) {
    return WorkflowCheckpoint(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString(),
      kind: _checkpointKindFromJson(json['kind']),
      taskNames: (json['taskNames'] as List?)?.cast<String>() ?? const [],
      autoVersion: json['autoVersion'] == true,
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Checkpoint name used for persistence and replay.
  final String name;

  /// Human-friendly checkpoint title exposed for introspection.
  final String title;

  /// Checkpoint kind classification.
  final WorkflowStepKind kind;

  final Object? Function(Object? value)? _valueEncoder;
  final Object? Function(Object? payload)? _valueDecoder;

  /// Task names associated with this checkpoint.
  final List<String> taskNames;

  /// Optional metadata associated with the checkpoint.
  final Map<String, Object?>? metadata;

  /// Whether to auto-version repeated checkpoint executions.
  final bool autoVersion;

  /// Serializes checkpoint metadata for workflow introspection.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      'title': title,
      'kind': kind.name,
      'taskNames': taskNames,
      'autoVersion': autoVersion,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Encodes a checkpoint value before it is persisted.
  Object? encodeValue(Object? value) {
    if (value == null) return null;
    final encoder = _valueEncoder;
    if (encoder == null) return value;
    return encoder(value);
  }

  /// Decodes a persisted checkpoint value back into the author-facing type.
  Object? decodeValue(Object? payload) {
    if (payload == null) return null;
    final decoder = _valueDecoder;
    if (decoder == null) return payload;
    return decoder(payload);
  }
}

WorkflowStepKind _checkpointKindFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return WorkflowStepKind.task;
  return WorkflowStepKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => WorkflowStepKind.task,
  );
}
