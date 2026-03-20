import 'package:stem/src/core/payload_codec.dart';

/// Typed read helpers for durable task-argument and workflow-parameter maps.
extension PayloadMapX on Map<String, Object?> {
  /// Returns the decoded value for [key], or `null` when the payload is absent.
  ///
  /// When [codec] is supplied, the stored durable payload is decoded through
  /// that codec before being returned.
  T? value<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = this[key];
    if (payload == null) return null;
    if (codec != null) {
      return codec.decode(payload);
    }
    return payload as T;
  }

  /// Returns the decoded value for [key], or [fallback] when it is absent.
  T valueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return value<T>(key, codec: codec) ?? fallback;
  }

  /// Returns the decoded value for [key], throwing when it is missing.
  T requiredValue<T>(String key, {PayloadCodec<T>? codec}) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return value<T>(key, codec: codec) as T;
  }
}
