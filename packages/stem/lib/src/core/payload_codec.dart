import 'dart:collection';

import 'package:stem/src/core/task_payload_encoder.dart';

/// Registry of version-specific payload decoders for a single durable DTO type.
///
/// Use this when a payload schema evolves over time and you want one reusable
/// place to define how each stored version should be decoded.
class PayloadVersionRegistry<T> {
  /// Creates a version registry from explicit [decoders].
  const PayloadVersionRegistry({
    required Map<int, T Function(Map<String, dynamic> payload)> decoders,
    this.defaultVersion,
  }) : _decoders = decoders;

  final Map<int, T Function(Map<String, dynamic> payload)> _decoders;

  /// Fallback version to use when a stored payload does not persist one.
  final int? defaultVersion;

  /// Registered decoder versions.
  Map<int, T Function(Map<String, dynamic> payload)> get decoders =>
      UnmodifiableMapView(_decoders);

  /// Decodes [payload] using the decoder registered for [version].
  T decode(
    Map<String, dynamic> payload,
    int version, {
    String typeName = 'payload',
  }) {
    final decoder = _decoders[version];
    if (decoder == null) {
      final known = _decoders.keys.toList()..sort();
      throw StateError(
        '$typeName has no decoder registered for payload version $version. '
        'Known versions: ${known.join(', ')}.',
      );
    }
    return decoder(payload);
  }
}

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
       _decodeVersionedMap = null,
       _jsonVersion = null,
       _defaultDecodeVersion = null,
       _typeName = null;

  /// Creates a payload codec for DTOs that serialize to a durable map payload.
  ///
  /// Use this when you need a custom map encoder or a decode function that is
  /// not the usual `Type.fromJson(...)` shape:
  ///
  /// ```dart
  /// const approvalCodec = PayloadCodec<Approval>.map(
  ///   encode: (value) => value.toJson(),
  ///   decode: Approval.fromJson,
  /// );
  /// ```
  const PayloadCodec.map({
    required Object? Function(T value) encode,
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) : _encode = encode,
       _decode = null,
       _decodeMap = decode,
       _decodeVersionedMap = null,
       _jsonVersion = null,
       _defaultDecodeVersion = null,
       _typeName = typeName;

  /// Creates a payload codec for map-backed DTO payloads that also persist a
  /// schema [version].
  ///
  /// Use this when a payload shape is expected to evolve over time and the
  /// decoder needs the stored schema version, but the payload still uses a
  /// custom map encoder or a nonstandard decode shape:
  ///
  /// ```dart
  /// const approvalCodec = PayloadCodec<Approval>.versionedMap(
  ///   encode: (value) => {'legacy_status': value.status},
  ///   version: 2,
  ///   defaultDecodeVersion: 1,
  ///   decode: Approval.fromVersionedMap,
  /// );
  /// ```
  const PayloadCodec.versionedMap({
    required Object? Function(T value) encode,
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) : _encode = encode,
       _decode = null,
       _decodeMap = null,
       _decodeVersionedMap = decode,
       _jsonVersion = version,
       _defaultDecodeVersion = defaultDecodeVersion,
       _typeName = typeName;

  /// Creates a payload codec for DTOs that expose `toJson()` and a matching
  /// typed decoder like `Type.fromJson(...)`.
  ///
  /// This is the shortest happy path for common DTO payloads:
  ///
  /// ```dart
  /// const approvalCodec = PayloadCodec<Approval>.json(
  ///   decode: Approval.fromJson,
  /// );
  /// ```
  const PayloadCodec.json({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) : _encode = _encodeJsonPayload,
       _decode = null,
       _decodeMap = decode,
       _decodeVersionedMap = null,
       _jsonVersion = null,
       _defaultDecodeVersion = null,
       _typeName = typeName;

  /// Creates a JSON DTO codec that also persists a schema version.
  ///
  /// Use this when a payload shape is expected to evolve over time and the
  /// decoder needs to know which persisted schema version it is reading.
  ///
  /// ```dart
  /// const approvalCodec = PayloadCodec<Approval>.versionedJson(
  ///   version: 2,
  ///   defaultDecodeVersion: 1,
  ///   decode: Approval.fromVersionedJson,
  /// );
  /// ```
  const PayloadCodec.versionedJson({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) : _encode = _encodeJsonPayload,
       _decode = null,
       _decodeMap = null,
       _decodeVersionedMap = decode,
       _jsonVersion = version,
       _defaultDecodeVersion = defaultDecodeVersion,
       _typeName = typeName;

  /// Creates a JSON DTO codec backed by a reusable version registry.
  ///
  /// This keeps payload version evolution in one place instead of repeating the
  /// same `switch(version)` logic across task, workflow, and event surfaces.
  factory PayloadCodec.versionedJsonRegistry({
    required int version,
    required PayloadVersionRegistry<T> registry,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      defaultDecodeVersion: defaultDecodeVersion ?? registry.defaultVersion,
      decode: (payload, storedVersion) => registry.decode(
        payload,
        storedVersion,
        typeName: typeName ?? '$T',
      ),
      typeName: typeName,
    );
  }

  /// Creates a custom map-backed codec backed by a reusable version registry.
  factory PayloadCodec.versionedMapRegistry({
    required Object? Function(T value) encode,
    required int version,
    required PayloadVersionRegistry<T> registry,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedMap(
      encode: encode,
      version: version,
      defaultDecodeVersion: defaultDecodeVersion ?? registry.defaultVersion,
      decode: (payload, storedVersion) => registry.decode(
        payload,
        storedVersion,
        typeName: typeName ?? '$T',
      ),
      typeName: typeName,
    );
  }

  /// Reserved key used to persist payload schema versions for versioned codecs.
  static const String versionKey = '__stemPayloadVersion';

  final Object? Function(T value) _encode;
  final T Function(Object? payload)? _decode;
  final T Function(Map<String, dynamic> payload)? _decodeMap;
  final T Function(Map<String, dynamic> payload, int version)?
  _decodeVersionedMap;
  final int? _jsonVersion;
  final int? _defaultDecodeVersion;
  final String? _typeName;

  /// Encodes a DTO to the string-keyed map shape required by task/workflow
  /// argument payloads.
  static Map<String, dynamic> encodeJsonMap<T>(
    T value, {
    String? typeName,
  }) {
    final payload = _encodeJsonPayload(value);
    return _payloadJsonMap(payload, typeName ?? value.runtimeType.toString());
  }

  /// Encodes a DTO to a string-keyed map and persists a schema [version]
  /// alongside the payload.
  static Map<String, dynamic> encodeVersionedJsonMap<T>(
    T value, {
    required int version,
    String? typeName,
  }) {
    return <String, dynamic>{
      versionKey: version,
      ...encodeJsonMap(value, typeName: typeName),
    };
  }

  /// Normalizes a durable payload into the string-keyed JSON map shape used by
  /// DTO-style decoders.
  static Map<String, dynamic> decodeJsonMap(
    Object? payload, {
    String typeName = 'payload',
  }) {
    return _payloadJsonMap(payload, typeName);
  }

  /// Reads the persisted schema version from a durable JSON payload.
  static int readPayloadVersion(
    Object? payload, {
    int defaultVersion = 1,
    String typeName = 'payload',
  }) {
    return _payloadVersion(
      _payloadJsonMap(payload, typeName),
      defaultVersion: defaultVersion,
      typeName: typeName,
    );
  }

  /// Converts a typed value into a durable payload representation.
  Object? encode(T value) {
    final encoded = _encode(value);
    final version = _jsonVersion;
    if (version == null) return encoded;
    final json = _payloadJsonMap(encoded, _typeName ?? '$T');
    return <String, dynamic>{
      versionKey: version,
      ...json,
    };
  }

  /// Reconstructs a typed value from a durable payload representation.
  T decode(Object? payload) {
    final decode = _decode;
    if (decode != null) {
      return decode(payload);
    }
    final decodeVersionedMap = _decodeVersionedMap;
    if (decodeVersionedMap != null) {
      final json = _payloadJsonMap(payload, _typeName ?? '$T');
      final version = _payloadVersion(
        json,
        defaultVersion: _defaultDecodeVersion ?? _jsonVersion ?? 1,
        typeName: _typeName ?? '$T',
      );
      final normalized = Map<String, dynamic>.from(json)..remove(versionKey);
      return decodeVersionedMap(normalized, version);
    }
    final decodeMap = _decodeMap!;
    return decodeMap(_payloadJsonMap(payload, _typeName ?? '$T'));
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

Object? _encodeJsonPayload<T>(T value) {
  try {
    final payload = (value as dynamic).toJson();
    return _payloadJsonMap(payload, value.runtimeType.toString());
    // Dynamic `toJson()` probing is the purpose of this helper.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    throw StateError(
      '${value.runtimeType} must expose toJson() to use PayloadCodec.json.',
    );
  }
}

Map<String, dynamic> _payloadJsonMap(Object? value, String typeName) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map<String, Object?>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    final result = <String, dynamic>{};
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
    '$typeName payload must decode to a string-keyed map, got '
    '${value.runtimeType}.',
  );
}

int _payloadVersion(
  Map<String, dynamic> payload, {
  required int defaultVersion,
  required String typeName,
}) {
  final rawVersion = payload[PayloadCodec.versionKey];
  if (rawVersion == null) return defaultVersion;
  if (rawVersion is int) return rawVersion;
  if (rawVersion is num) return rawVersion.toInt();
  if (rawVersion is String) {
    final parsed = int.tryParse(rawVersion);
    if (parsed != null) return parsed;
  }
  throw StateError(
    '$typeName payload version must be an int-compatible value, got '
    '${rawVersion.runtimeType}.',
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
