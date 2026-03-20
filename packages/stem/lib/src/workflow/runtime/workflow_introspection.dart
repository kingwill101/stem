import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/core/stem_event.dart';

/// Enumerates workflow step event types emitted by the runtime.
enum WorkflowStepEventType {
  /// Step execution started.
  started,

  /// Step execution completed successfully.
  completed,

  /// Step execution failed.
  failed,

  /// Step execution is retrying.
  retrying,
}

/// Runtime-level workflow events emitted by orchestration transitions.
enum WorkflowRuntimeEventType {
  /// A continuation task was enqueued for a run.
  continuationEnqueued,
}

/// Step-level execution event emitted by the workflow runtime.
class WorkflowStepEvent implements StemEvent {
  /// Creates a workflow step execution event.
  WorkflowStepEvent({
    required this.runId,
    required this.workflow,
    required this.stepId,
    required this.type,
    required this.timestamp,
    this.iteration,
    this.result,
    this.error,
    this.metadata,
  });

  /// Workflow run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Step identifier.
  final String stepId;

  /// Event type.
  final WorkflowStepEventType type;

  /// Timestamp when the event was recorded.
  final DateTime timestamp;

  /// Optional step iteration for auto-versioned steps.
  final int? iteration;

  /// Optional result payload for completed steps.
  final Object? result;

  /// Decodes the step result payload with [codec], when present.
  TResult? resultAs<TResult>({required PayloadCodec<TResult> codec}) {
    final stored = result;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the step result payload with a JSON decoder, when present.
  TResult? resultJson<TResult>({
    required TResult Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = result;
    if (stored == null) return null;
    return PayloadCodec<TResult>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the step result payload with a version-aware JSON decoder, when
  /// present.
  TResult? resultVersionedJson<TResult>({
    required int version,
    required TResult Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = result;
    if (stored == null) return null;
    return PayloadCodec<TResult>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Optional error message for failed steps.
  final String? error;

  /// Optional metadata associated with the event.
  final Map<String, Object?>? metadata;

  /// Returns the decoded metadata value for [key], or `null` when absent.
  T? metadataValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with [codec].
  T? metadataAs<T>(String key, {required PayloadCodec<T> codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with a JSON decoder.
  T? metadataJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Decodes the metadata value for [key] as a typed DTO with a version-aware
  /// JSON decoder.
  T? metadataVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.valueVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Decodes the full metadata payload as a typed DTO with [codec].
  T? metadataPayloadAs<T>({required PayloadCodec<T> codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return codec.decode(payload);
  }

  /// Decodes the full metadata payload as a typed DTO with a JSON decoder.
  T? metadataPayloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the full metadata payload as a typed DTO with a version-aware
  /// JSON decoder.
  T? metadataPayloadVersionedJson<T>({
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion ?? defaultVersion,
      typeName: typeName,
    ).decode(payload);
  }

  @override
  String get eventName => 'workflow.step.${type.name}';

  @override
  DateTime get occurredAt => timestamp;

  @override
  Map<String, Object?> get attributes => {
    'runId': runId,
    'workflow': workflow,
    'stepId': stepId,
    if (iteration != null) 'iteration': iteration,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Runtime orchestration event emitted by the workflow runtime.
class WorkflowRuntimeEvent implements StemEvent {
  /// Creates a runtime orchestration event.
  WorkflowRuntimeEvent({
    required this.runId,
    required this.workflow,
    required this.type,
    required this.timestamp,
    this.metadata,
  });

  /// Workflow run identifier.
  final String runId;

  /// Workflow name.
  final String workflow;

  /// Runtime event type.
  final WorkflowRuntimeEventType type;

  /// Event timestamp.
  final DateTime timestamp;

  /// Additional event metadata.
  final Map<String, Object?>? metadata;

  /// Returns the decoded metadata value for [key], or `null` when absent.
  T? metadataValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with [codec].
  T? metadataAs<T>(String key, {required PayloadCodec<T> codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Decodes the metadata value for [key] as a typed DTO with a JSON decoder.
  T? metadataJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Decodes the metadata value for [key] as a typed DTO with a version-aware
  /// JSON decoder.
  T? metadataVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return payload.valueVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Decodes the full metadata payload as a typed DTO with [codec].
  T? metadataPayloadAs<T>({required PayloadCodec<T> codec}) {
    final payload = metadata;
    if (payload == null) return null;
    return codec.decode(payload);
  }

  /// Decodes the full metadata payload as a typed DTO with a JSON decoder.
  T? metadataPayloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the full metadata payload as a typed DTO with a version-aware
  /// JSON decoder.
  T? metadataPayloadVersionedJson<T>({
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = metadata;
    if (payload == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion ?? defaultVersion,
      typeName: typeName,
    ).decode(payload);
  }

  @override
  String get eventName => 'workflow.runtime.${type.name}';

  @override
  DateTime get occurredAt => timestamp;

  @override
  Map<String, Object?> get attributes => {
    'runId': runId,
    'workflow': workflow,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Sink for workflow step execution events.
mixin WorkflowIntrospectionSink {
  /// Records a workflow step execution [event].
  Future<void> recordStepEvent(WorkflowStepEvent event);

  /// Records a workflow runtime [event]. Optional for sinks that only care
  /// about step-level traces.
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}

/// Default no-op sink for workflow step events.
class NoopWorkflowIntrospectionSink implements WorkflowIntrospectionSink {
  /// Creates a no-op introspection sink.
  const NoopWorkflowIntrospectionSink();

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {}

  @override
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {}
}
