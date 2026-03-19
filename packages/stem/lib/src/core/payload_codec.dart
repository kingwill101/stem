import 'package:stem/src/core/task_payload_encoder.dart';

/// Encodes and decodes a strongly-typed payload value.
///
/// This author-facing codec layer is used by generated workflow/task helpers to
/// lower richer Dart DTOs into the existing durable wire format.
class PayloadCodec<T> {
  /// Creates a payload codec from explicit encode/decode callbacks.
  const PayloadCodec({required this.encode, required this.decode});

  /// Converts a typed value into a durable payload representation.
  final Object? Function(T value) encode;

  /// Reconstructs a typed value from a durable payload representation.
  final T Function(Object? payload) decode;

  /// Converts an erased author-facing value into a durable payload.
  Object? encodeDynamic(Object? value) {
    if (value == null) return null;
    return encode(value as T);
  }

  /// Reconstructs an erased author-facing value from a durable payload.
  Object? decodeDynamic(Object? payload) {
    if (payload == null) return null;
    return decode(payload);
  }
}

/// Bridges a [PayloadCodec] into the existing [TaskPayloadEncoder] contract.
class CodecTaskPayloadEncoder<T> extends TaskPayloadEncoder {
  /// Creates a task payload encoder backed by a typed [codec].
  const CodecTaskPayloadEncoder({required this.idValue, required this.codec});

  /// Stable encoder identifier used across producer/worker boundaries.
  final String idValue;

  /// Typed codec used to encode and decode payloads.
  final PayloadCodec<T> codec;

  @override
  String get id => idValue;

  @override
  Object? encode(Object? value) {
    return codec.encodeDynamic(value);
  }

  @override
  Object? decode(Object? stored) {
    return codec.decodeDynamic(stored);
  }
}
