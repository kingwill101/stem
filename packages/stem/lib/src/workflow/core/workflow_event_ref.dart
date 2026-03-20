import 'package:stem/src/core/payload_codec.dart';

/// Shared typed workflow-event dispatch surface used by apps and runtimes.
abstract interface class WorkflowEventEmitter {
  /// Emits a typed external event that serializes onto the durable map-based
  /// workflow event transport.
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  });

  /// Emits a typed external event using a [WorkflowEventRef].
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value);
}

/// Typed reference to a workflow resume event topic.
///
/// This bundles the durable topic name with an optional payload codec so
/// callers do not need to repeat a raw topic string and separate codec across
/// wait and emit sites.
class WorkflowEventRef<T> {
  /// Creates a typed workflow event reference.
  const WorkflowEventRef({
    required this.topic,
    this.codec,
  });

  /// Durable topic name used to suspend and resume workflow runs.
  final String topic;

  /// Optional codec for encoding and decoding event payloads.
  final PayloadCodec<T>? codec;

  /// Builds a typed event emission call from [value].
  WorkflowEventCall<T> call(T value) {
    return WorkflowEventCall._(event: this, value: value);
  }
}

/// Typed event emission request built from a [WorkflowEventRef].
class WorkflowEventCall<T> {
  const WorkflowEventCall._({
    required this.event,
    required this.value,
  });

  /// Reference used to build this event emission.
  final WorkflowEventRef<T> event;

  /// Typed event payload.
  final T value;

  /// Durable topic name derived from [event].
  String get topic => event.topic;
}

/// Convenience helpers for dispatching typed workflow events.
extension WorkflowEventRefExtension<T> on WorkflowEventRef<T> {
  /// Emits this typed event with the provided [emitter].
  Future<void> emitWith(WorkflowEventEmitter emitter, T value) {
    return emitter.emitEvent(this, value);
  }
}

/// Convenience helpers for dispatching prebuilt [WorkflowEventCall] instances.
extension WorkflowEventCallExtension<T> on WorkflowEventCall<T> {
  /// Emits this typed event with the provided [emitter].
  Future<void> emitWith(WorkflowEventEmitter emitter) {
    return emitter.emitEvent(event, value);
  }
}

/// Caller-bound typed workflow event emission call.
class BoundWorkflowEventCall<T> {
  /// Creates a caller-bound typed workflow event emission call.
  const BoundWorkflowEventCall._({
    required WorkflowEventEmitter emitter,
    required WorkflowEventCall<T> call,
  }) : _emitter = emitter,
       _call = call;

  final WorkflowEventEmitter _emitter;
  final WorkflowEventCall<T> _call;

  /// Returns the prebuilt typed workflow event call.
  WorkflowEventCall<T> build() => _call;

  /// Emits the bound typed workflow event call.
  Future<void> emit() => _call.emitWith(_emitter);
}

/// Convenience helpers for building typed workflow event calls directly from a
/// workflow event emitter.
extension WorkflowEventEmitterBuilderExtension on WorkflowEventEmitter {
  /// Creates a caller-bound typed workflow event call for [event] and [value].
  BoundWorkflowEventCall<T> emitEventBuilder<T>({
    required WorkflowEventRef<T> event,
    required T value,
  }) {
    return BoundWorkflowEventCall._(
      emitter: this,
      call: event.call(value),
    );
  }
}
