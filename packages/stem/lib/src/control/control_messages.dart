import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';

/// Control-plane command dispatched to worker control queues.
class ControlCommandMessage {
  /// Creates a command message for worker control queues.
  ControlCommandMessage({
    required this.requestId,
    required this.type,
    required this.targets,
    Map<String, Object?>? payload,
    this.timeoutMs,
  }) : payload = payload ?? const {};

  /// Hydrates a control command from a serialized map payload.
  factory ControlCommandMessage.fromMap(Map<String, Object?> map) {
    return ControlCommandMessage(
      requestId: map['requestId']! as String,
      type: map['type']! as String,
      targets: (map['targets'] as List?)?.cast<String>() ?? const ['*'],
      payload: (map['payload'] as Map?)?.cast<String, Object?>(),
      timeoutMs: (map['timeoutMs'] as num?)?.toInt(),
    );
  }

  /// Correlation id used to match replies.
  final String requestId;

  /// Command type identifier.
  final String type;

  /// Target worker identifiers or wildcards.
  final List<String> targets;

  /// Arbitrary command payload.
  final Map<String, Object?> payload;

  /// Returns the decoded payload value for [key], or `null` when absent.
  T? payloadValue<T>(String key, {PayloadCodec<T>? codec}) {
    return payload.value<T>(key, codec: codec);
  }

  /// Returns the decoded payload value for [key], or [fallback] when absent.
  T payloadValueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return payload.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded payload value for [key], throwing when absent.
  T requiredPayloadValue<T>(String key, {PayloadCodec<T>? codec}) {
    return payload.requiredValue<T>(key, codec: codec);
  }

  /// Decodes the full payload as a typed DTO with [codec].
  T payloadAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(payload);
  }

  /// Decodes the full payload as a typed DTO with a JSON decoder.
  T payloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the full payload as a typed DTO with a version-aware JSON
  /// decoder.
  T payloadVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(payload);
  }

  /// Optional timeout for the command, in milliseconds.
  final int? timeoutMs;

  /// Serializes the command into a map payload.
  Map<String, Object?> toMap() => {
    'requestId': requestId,
    'type': type,
    'targets': targets,
    'payload': payload,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
  };
}

/// Control-plane reply emitted by a worker in response to a command.
class ControlReplyMessage {
  /// Creates a reply message for a control command.
  ControlReplyMessage({
    required this.requestId,
    required this.workerId,
    required this.status,
    Map<String, Object?>? payload,
    this.error,
  }) : payload = payload ?? const {};

  /// Hydrates a control reply from a serialized map payload.
  factory ControlReplyMessage.fromMap(Map<String, Object?> map) {
    return ControlReplyMessage(
      requestId: map['requestId']! as String,
      workerId: map['workerId']! as String,
      status: map['status']! as String,
      payload: (map['payload'] as Map?)?.cast<String, Object?>(),
      error: (map['error'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Correlation id referencing the originating command.
  final String requestId;

  /// Worker id that produced the reply.
  final String workerId;

  /// Reply status string.
  final String status;

  /// Arbitrary reply payload.
  final Map<String, Object?> payload;

  /// Returns the decoded payload value for [key], or `null` when absent.
  T? payloadValue<T>(String key, {PayloadCodec<T>? codec}) {
    return payload.value<T>(key, codec: codec);
  }

  /// Returns the decoded payload value for [key], or [fallback] when absent.
  T payloadValueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return payload.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded payload value for [key], throwing when absent.
  T requiredPayloadValue<T>(String key, {PayloadCodec<T>? codec}) {
    return payload.requiredValue<T>(key, codec: codec);
  }

  /// Decodes the full payload as a typed DTO with [codec].
  T payloadAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(payload);
  }

  /// Decodes the full payload as a typed DTO with a JSON decoder.
  T payloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the full payload as a typed DTO with a version-aware JSON
  /// decoder.
  T payloadVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(payload);
  }

  /// Optional error payload.
  final Map<String, Object?>? error;

  /// Returns the decoded error value for [key], or `null` when absent.
  T? errorValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = error;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Returns the decoded error value for [key], or [fallback] when absent.
  T errorValueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    final payload = error;
    if (payload == null) return fallback;
    return payload.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded error value for [key], throwing when absent.
  T requiredErrorValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = error;
    if (payload == null) {
      throw StateError('ControlReplyMessage.error does not contain "$key".');
    }
    return payload.requiredValue<T>(key, codec: codec);
  }

  /// Decodes the full error payload as a typed DTO with [codec].
  T? errorAs<T>({required PayloadCodec<T> codec}) {
    final payload = error;
    if (payload == null) return null;
    return codec.decode(payload);
  }

  /// Decodes the full error payload as a typed DTO with a JSON decoder.
  T? errorJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = error;
    if (payload == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the full error payload as a typed DTO with a version-aware JSON
  /// decoder.
  T? errorVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = error;
    if (payload == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(payload);
  }

  /// Serializes the reply into a map payload.
  Map<String, Object?> toMap() => {
    'requestId': requestId,
    'workerId': workerId,
    'status': status,
    'payload': payload,
    if (error != null) 'error': error,
  };
}

/// Helpers for building control queue names.
abstract class ControlQueueNames {
  /// Queue name for a specific worker.
  static String worker(String namespace, String workerId) =>
      '$namespace.control.worker.$workerId';

  /// Queue name for broadcast control messages.
  static String broadcast(String namespace) => '$namespace.control.broadcast';

  /// Queue name for replies associated with a request.
  static String reply(String namespace, String requestId) =>
      '$namespace.control.reply.$requestId';
}

/// Envelope name constants used by control messages.
class ControlEnvelopeTypes {
  /// Envelope name for control commands.
  static const command = '__stem.control__';

  /// Envelope name for control replies.
  static const reply = '__stem.control.reply__';
}

/// Extension helpers to convert a command into an [Envelope].
extension ControlCommandEnvelope on ControlCommandMessage {
  /// Encodes the command as an [Envelope] for dispatch.
  Envelope toEnvelope({required String queue, Map<String, String>? headers}) {
    return Envelope(
      name: ControlEnvelopeTypes.command,
      queue: queue,
      args: toMap(),
      headers: {'stem-control': '1', if (headers != null) ...headers},
    );
  }
}

/// Extension helpers to convert a reply into an [Envelope].
extension ControlReplyEnvelope on ControlReplyMessage {
  /// Encodes the reply as an [Envelope] for dispatch.
  Envelope toEnvelope({required String queue, Map<String, String>? headers}) {
    return Envelope(
      name: ControlEnvelopeTypes.reply,
      queue: queue,
      args: toMap(),
      headers: {'stem-control-reply': '1', if (headers != null) ...headers},
    );
  }
}

/// Parses a [ControlReplyMessage] from a control reply [Envelope].
ControlReplyMessage controlReplyFromEnvelope(Envelope envelope) {
  return ControlReplyMessage.fromMap(
    envelope.args.map(MapEntry.new),
  );
}

/// Parses a [ControlCommandMessage] from a control command [Envelope].
ControlCommandMessage controlCommandFromEnvelope(Envelope envelope) {
  return ControlCommandMessage.fromMap(
    envelope.args.map(MapEntry.new),
  );
}
