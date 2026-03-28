import 'dart:async';

import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow.dart' show Flow;
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/workflow.dart' show Flow;
import 'package:stem/stem.dart' show Flow;

/// Kinds of workflow steps exposed for introspection.
enum WorkflowStepKind {
  /// Step executes a task-like handler.
  task,

  /// Step represents a choice/branching decision.
  choice,

  /// Step represents parallel work.
  parallel,

  /// Step represents a wait/suspension.
  wait,

  /// Step has custom semantics not captured by the built-in kinds.
  custom,
}

/// Node in a workflow [Flow].
///
/// The [handler] may execute multiple times when a run resumes from a
/// suspension or retry. Ensure the logic is idempotent and uses values stored
/// in the [FlowContext] (e.g. via `context.previousResult` or
/// `context.takeResumeData()`). When [autoVersion] is `true`, each time the
/// step completes its checkpoint is stored as `<name>#<iteration>` so repeated
/// executions do not overwrite previous results.
class FlowStep {
  /// Creates a workflow step definition.
  FlowStep({
    required this.name,
    required this.handler,
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

  /// Rehydrates a flow step from serialized JSON.
  factory FlowStep.fromJson(Map<String, Object?> json) {
    return FlowStep(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString(),
      kind: _kindFromJson(json['kind']),
      taskNames: (json['taskNames'] as List?)?.cast<String>() ?? const [],
      autoVersion: json['autoVersion'] == true,
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
      handler: (_) async {},
    );
  }

  /// Creates a step definition backed by a typed [valueCodec].
  static FlowStep typed<T>({
    required String name,
    required FutureOr<dynamic> Function(FlowContext context) handler,
    required PayloadCodec<T> valueCodec,
    bool autoVersion = false,
    String? title,
    WorkflowStepKind kind = WorkflowStepKind.task,
    Iterable<String> taskNames = const [],
    Map<String, Object?>? metadata,
  }) {
    return FlowStep(
      name: name,
      handler: handler,
      autoVersion: autoVersion,
      title: title,
      valueEncoder: valueCodec.encodeDynamic,
      valueDecoder: valueCodec.decodeDynamic,
      kind: kind,
      taskNames: taskNames,
      metadata: metadata,
    );
  }

  /// Step name used for checkpoints and scheduling.
  final String name;

  /// Human-friendly step title exposed for introspection.
  final String title;

  /// Step kind classification.
  final WorkflowStepKind kind;

  final Object? Function(Object? value)? _valueEncoder;
  final Object? Function(Object? payload)? _valueDecoder;

  /// Task names associated with this step (for UI introspection).
  final List<String> taskNames;

  /// Optional metadata associated with the step.
  final Map<String, Object?>? metadata;

  /// Handler invoked when the step executes.
  final FutureOr<dynamic> Function(FlowContext context) handler;

  /// Whether to auto-version checkpoints across repeated executions.
  final bool autoVersion;

  /// Serialize step metadata for workflow introspection.
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

  /// Encodes a step value before it is persisted.
  Object? encodeValue(Object? value) {
    if (value == null) return null;
    final encoder = _valueEncoder;
    if (encoder == null) return value;
    return encoder(value);
  }

  /// Decodes a persisted step value back into the author-facing type.
  Object? decodeValue(Object? payload) {
    if (payload == null) return null;
    final decoder = _valueDecoder;
    if (decoder == null) return payload;
    return decoder(payload);
  }
}

WorkflowStepKind _kindFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return WorkflowStepKind.task;
  return WorkflowStepKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => WorkflowStepKind.task,
  );
}

/// Control directive emitted by a workflow step to suspend execution.
class FlowStepControl {
  /// Creates a control directive with the given [type].
  FlowStepControl._(
    this.type, {
    this.delay,
    this.topic,
    this.deadline,
    this.data,
  });

  /// Suspend the run until [duration] elapses.
  factory FlowStepControl.sleep(
    Duration duration, {
    Map<String, Object?>? data,
  }) => FlowStepControl._(FlowControlType.sleep, delay: duration, data: data);

  /// Suspend the run until an event with [topic] arrives.
  factory FlowStepControl.awaitTopic(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) => FlowStepControl._(
    FlowControlType.waitForEvent,
    topic: topic,
    deadline: deadline,
    data: data,
  );

  /// Continue execution without suspending.
  factory FlowStepControl.continueRun() =>
      FlowStepControl._(FlowControlType.continueRun);

  /// Suspend the run until [duration] elapses with a DTO payload.
  static FlowStepControl sleepJson<T>(
    Duration duration,
    T value, {
    String? typeName,
  }) => FlowStepControl.sleep(
    duration,
    data: Map<String, Object?>.from(
      PayloadCodec.encodeJsonMap(value, typeName: typeName),
    ),
  );

  /// Suspend the run until [duration] elapses with a versioned DTO payload.
  static FlowStepControl sleepVersionedJson<T>(
    Duration duration,
    T value, {
    required int version,
    String? typeName,
  }) => FlowStepControl.sleep(
    duration,
    data: Map<String, Object?>.from(
      PayloadCodec.encodeVersionedJsonMap(
        value,
        version: version,
        typeName: typeName,
      ),
    ),
  );

  /// Suspend the run until an event with [topic] arrives with a DTO payload.
  static FlowStepControl awaitTopicJson<T>(
    String topic,
    T value, {
    DateTime? deadline,
    String? typeName,
  }) => FlowStepControl.awaitTopic(
    topic,
    deadline: deadline,
    data: Map<String, Object?>.from(
      PayloadCodec.encodeJsonMap(value, typeName: typeName),
    ),
  );

  /// Suspend the run until an event with [topic] arrives with a versioned DTO
  /// payload.
  static FlowStepControl awaitTopicVersionedJson<T>(
    String topic,
    T value, {
    required int version,
    DateTime? deadline,
    String? typeName,
  }) => FlowStepControl.awaitTopic(
    topic,
    deadline: deadline,
    data: Map<String, Object?>.from(
      PayloadCodec.encodeVersionedJsonMap(
        value,
        version: version,
        typeName: typeName,
      ),
    ),
  );

  /// Control type emitted by the step.
  final FlowControlType type;

  /// Delay duration for sleep directives.
  final Duration? delay;

  /// Topic to await for event directives.
  final String? topic;

  /// Optional deadline for event waits.
  final DateTime? deadline;

  /// Additional data to persist with the suspension.
  final Map<String, Object?>? data;

  /// Decodes the suspension metadata with [codec], when present.
  TData? dataAs<TData>({required PayloadCodec<TData> codec}) {
    final stored = data;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the suspension metadata with a JSON decoder, when present.
  TData? dataJson<TData>({
    required TData Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = data;
    if (stored == null) return null;
    return PayloadCodec<TData>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the suspension metadata with a version-aware JSON decoder, when
  /// present.
  TData? dataVersionedJson<TData>({
    required int version,
    required TData Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = data;
    if (stored == null) return null;
    return PayloadCodec<TData>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }
}

/// Enumerates the suspension control types.
enum FlowControlType {
  /// Continue execution immediately.
  continueRun,

  /// Suspend execution for a duration.
  sleep,

  /// Suspend execution until an event is received.
  waitForEvent,
}
