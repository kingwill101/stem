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

  /// Creates a typed workflow event reference for DTO payloads that already
  /// expose `toJson()` and `Type.fromJson(...)`.
  factory WorkflowEventRef.codec({
    required String topic,
    required PayloadCodec<T> codec,
  }) {
    return WorkflowEventRef<T>(
      topic: topic,
      codec: codec,
    );
  }

  /// Creates a typed workflow event reference for DTO payloads that already
  /// expose `toJson()` and `Type.fromJson(...)`.
  factory WorkflowEventRef.json({
    required String topic,
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return WorkflowEventRef<T>.codec(
      topic: topic,
      codec: PayloadCodec<T>.json(
        decode: decode,
        typeName: typeName,
      ),
    );
  }

  /// Creates a typed workflow event reference for DTO payloads that already
  /// expose `toJson()` and persist a schema [version] beside the payload.
  factory WorkflowEventRef.versionedJson({
    required String topic,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return WorkflowEventRef<T>.codec(
      topic: topic,
      codec: PayloadCodec<T>.versionedJson(
        version: version,
        decode: decode,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: typeName,
      ),
    );
  }

  /// Creates a typed workflow event reference backed by a reusable version
  /// registry.
  factory WorkflowEventRef.versionedJsonRegistry({
    required String topic,
    required int version,
    required PayloadVersionRegistry<T> registry,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return WorkflowEventRef<T>.codec(
      topic: topic,
      codec: PayloadCodec<T>.versionedJsonRegistry(
        version: version,
        registry: registry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: typeName,
      ),
    );
  }

  /// Creates a typed workflow event reference for custom map payloads that
  /// persist a schema [version] beside the payload.
  factory WorkflowEventRef.versionedMap({
    required String topic,
    required Object? Function(T value) encode,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return WorkflowEventRef<T>.codec(
      topic: topic,
      codec: PayloadCodec<T>.versionedMap(
        encode: encode,
        version: version,
        decode: decode,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: typeName,
      ),
    );
  }

  /// Creates a typed workflow event reference for custom map payloads backed
  /// by a reusable version registry.
  factory WorkflowEventRef.versionedMapRegistry({
    required String topic,
    required Object? Function(T value) encode,
    required int version,
    required PayloadVersionRegistry<T> registry,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return WorkflowEventRef<T>.codec(
      topic: topic,
      codec: PayloadCodec<T>.versionedMapRegistry(
        encode: encode,
        version: version,
        registry: registry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: typeName,
      ),
    );
  }

  /// Durable topic name used to suspend and resume workflow runs.
  final String topic;

  /// Optional codec for encoding and decoding event payloads.
  final PayloadCodec<T>? codec;

}

/// Convenience helpers for dispatching typed workflow events.
extension WorkflowEventRefExtension<T> on WorkflowEventRef<T> {
  /// Emits this typed event with the provided [emitter].
  Future<void> emit(WorkflowEventEmitter emitter, T value) {
    return emitter.emitEvent(this, value);
  }
}
