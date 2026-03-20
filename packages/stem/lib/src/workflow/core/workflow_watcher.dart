import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/payload_codec.dart';

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
      createdAt: _dateFromJson(json['createdAt']) ?? stemNow().toUtc(),
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

  /// Suspension type (`sleep`, `event`, etc.) when recorded by runtime.
  String? get suspensionType => data['type']?.toString();

  /// Workflow iteration value when present.
  int? get iteration => _intFromJson(data['iteration']);

  /// Iteration step marker when present.
  String? get iterationStep => data['iterationStep']?.toString();

  /// Effective payload snapshot captured at suspension time.
  Object? get payload => data['payload'];

  /// Decodes the captured watcher payload with [codec], when present.
  TPayload? payloadAs<TPayload>({required PayloadCodec<TPayload> codec}) {
    final stored = payload;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the captured watcher payload with a JSON decoder, when present.
  TPayload? payloadJson<TPayload>({
    required TPayload Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<TPayload>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the captured watcher payload with a version-aware JSON decoder,
  /// when present.
  TPayload? payloadVersionedJson<TPayload>({
    required int version,
    required TPayload Function(
      Map<String, dynamic> payload,
      int version,
    )
    decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<TPayload>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Timestamp when suspension was recorded.
  DateTime? get suspendedAt => _dateFromJson(data['suspendedAt']);

  /// Requested resume timestamp when a policy is active.
  DateTime? get requestedResumeAt => _dateFromJson(data['requestedResumeAt']);

  /// Timeout deadline chosen by the policy/runtime.
  DateTime? get policyDeadline => _dateFromJson(data['policyDeadline']);

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

  /// Suspension type (`sleep`, `event`, etc.) propagated to resume payload.
  String? get suspensionType => resumeData['type']?.toString();

  /// Workflow iteration value when present.
  int? get iteration => _intFromJson(resumeData['iteration']);

  /// Iteration step marker when present.
  String? get iterationStep => resumeData['iterationStep']?.toString();

  /// Resume payload delivered to workflow step.
  Object? get payload => resumeData['payload'];

  /// Decodes the resume payload with [codec], when present.
  TPayload? payloadAs<TPayload>({required PayloadCodec<TPayload> codec}) {
    final stored = payload;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the resume payload with a JSON decoder, when present.
  TPayload? payloadJson<TPayload>({
    required TPayload Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<TPayload>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the resume payload with a version-aware JSON decoder, when
  /// present.
  TPayload? payloadVersionedJson<TPayload>({
    required int version,
    required TPayload Function(
      Map<String, dynamic> payload,
      int version,
    )
    decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<TPayload>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Timestamp when event delivery was recorded.
  DateTime? get deliveredAt => _dateFromJson(resumeData['deliveredAt']);

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

int? _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
