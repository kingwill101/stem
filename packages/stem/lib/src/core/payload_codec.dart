import 'package:stem/src/core/task_payload_encoder.dart';

/// Encodes and decodes a strongly-typed payload value.
///
/// This author-facing codec layer is used by generated workflow/task helpers to
/// lower richer Dart DTOs into the existing durable wire format.
class PayloadCodec<T> {
  /// Creates a payload codec from explicit encode/decode callbacks.
  const PayloadCodec({
    required Object? Function(T value) encode,
    required T Function(Object? payload) decode,
  }) : _encode = encode,
       _decode = decode,
       _decodeMap = null,
       _typeName = null;

  /// Creates a payload codec for DTOs that serialize to a durable map payload.
  ///
  /// This is the common author-facing case for workflow/task DTOs:
  ///
  /// ```dart
  /// const approvalCodec = PayloadCodec<Approval>.map(
  ///   encode: (value) => value.toJson(),
  ///   decode: Approval.fromJson,
  /// );
  /// ```
  const PayloadCodec.map({
    required Object? Function(T value) encode,
    required T Function(Map<String, Object?> payload) decode,
    String? typeName,
  }) : _encode = encode,
       _decode = null,
       _decodeMap = decode,
       _typeName = typeName;

  final Object? Function(T value) _encode;
  final T Function(Object? payload)? _decode;
  final T Function(Map<String, Object?> payload)? _decodeMap;
  final String? _typeName;

  /// Converts a typed value into a durable payload representation.
  Object? encode(T value) => _encode(value);

  /// Reconstructs a typed value from a durable payload representation.
  T decode(Object? payload) {
    final decode = _decode;
    if (decode != null) {
      return decode(payload);
    }
    final decodeMap = _decodeMap!;
    return decodeMap(_payloadMap(payload, _typeName ?? '$T'));
  }

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

Map<String, Object?> _payloadMap(Object? value, String typeName) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw StateError('$typeName payload must use string keys.');
      }
      result[key] = entry.value;
    }
    return result;
  }
  throw StateError(
    '$typeName payload must decode to Map<String, Object?>, got '
    '${value.runtimeType}.',
  );
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
