import 'package:stem/src/core/envelope.dart';

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

  /// Optional error payload.
  final Map<String, Object?>? error;

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
