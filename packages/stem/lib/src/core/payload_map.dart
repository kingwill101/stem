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

  /// Decodes the value for [key] as a typed DTO with a JSON decoder.
  T? valueJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = this[key];
    if (payload == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the value for [key] as a typed DTO with a version-aware JSON
  /// decoder.
  T? valueVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = this[key];
    if (payload == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion ?? defaultVersion,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the value for [key] as a typed DTO, or [fallback] when absent.
  T valueJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return valueJson<T>(
          key,
          decode: decode,
          typeName: typeName,
        ) ??
        fallback;
  }

  /// Decodes the value for [key] as a typed DTO, throwing when absent.
  T requiredValueJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    ) as T;
  }

  /// Decodes the value for [key] as a version-aware typed DTO, or [fallback]
  /// when absent.
  T valueVersionedJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return valueVersionedJson<T>(
          key,
          defaultVersion: defaultVersion,
          decode: decode,
          defaultDecodeVersion: defaultDecodeVersion,
          typeName: typeName,
        ) ??
        fallback;
  }

  /// Decodes the value for [key] as a version-aware typed DTO, throwing when
  /// absent.
  T requiredValueVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return valueVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ) as T;
  }

  /// Returns the decoded list value for [key], or `null` when it is absent.
  ///
  /// When [codec] is supplied, each stored durable payload is decoded through
  /// that codec before being returned.
  List<T>? valueList<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = this[key];
    if (payload == null) return null;
    final values = payload as List;
    if (codec != null) {
      return List<T>.unmodifiable(values.map(codec.decode));
    }
    return List<T>.unmodifiable(values.cast<T>());
  }

  /// Returns the decoded list value for [key], or [fallback] when it is
  /// absent.
  List<T> valueListOr<T>(
    String key,
    List<T> fallback, {
    PayloadCodec<T>? codec,
  }) {
    return valueList<T>(key, codec: codec) ?? fallback;
  }

  /// Returns the decoded list value for [key], throwing when it is missing.
  List<T> requiredValueList<T>(String key, {PayloadCodec<T>? codec}) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return valueList<T>(key, codec: codec)!;
  }

  /// Returns the decoded DTO list value for [key], or `null` when it is
  /// absent.
  List<T>? valueListJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = this[key];
    if (payload == null) return null;
    final values = payload as List;
    final codec = PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    );
    return List<T>.unmodifiable(values.map(codec.decode));
  }

  /// Returns the decoded version-aware DTO list value for [key], or `null`
  /// when it is absent.
  List<T>? valueListVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = this[key];
    if (payload == null) return null;
    final values = payload as List;
    final codec = PayloadCodec<T>.versionedJson(
      version: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion ?? defaultVersion,
      typeName: typeName,
    );
    return List<T>.unmodifiable(values.map(codec.decode));
  }

  /// Returns the decoded DTO list value for [key], or [fallback] when absent.
  List<T> valueListJsonOr<T>(
    String key,
    List<T> fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return valueListJson<T>(
          key,
          decode: decode,
          typeName: typeName,
        ) ??
        fallback;
  }

  /// Returns the decoded DTO list value for [key], throwing when absent.
  List<T> requiredValueListJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return valueListJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    )!;
  }

  /// Returns the decoded version-aware DTO list value for [key], or
  /// [fallback] when absent.
  List<T> valueListVersionedJsonOr<T>(
    String key,
    List<T> fallback, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return valueListVersionedJson<T>(
          key,
          defaultVersion: defaultVersion,
          decode: decode,
          defaultDecodeVersion: defaultDecodeVersion,
          typeName: typeName,
        ) ??
        fallback;
  }

  /// Returns the decoded version-aware DTO list value for [key], throwing when
  /// absent.
  List<T> requiredValueListVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError("Missing required payload key '$key'.");
    }
    return valueListVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    )!;
  }
}
