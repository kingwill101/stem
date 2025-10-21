import '../core/envelope.dart';

class ControlCommandMessage {
  ControlCommandMessage({
    required this.requestId,
    required this.type,
    required this.targets,
    Map<String, Object?>? payload,
    this.timeoutMs,
  }) : payload = payload ?? const {};

  final String requestId;
  final String type;
  final List<String> targets;
  final Map<String, Object?> payload;
  final int? timeoutMs;

  Map<String, Object?> toMap() => {
        'requestId': requestId,
        'type': type,
        'targets': targets,
        'payload': payload,
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
      };

  factory ControlCommandMessage.fromMap(Map<String, Object?> map) {
    return ControlCommandMessage(
      requestId: map['requestId'] as String,
      type: map['type'] as String,
      targets: (map['targets'] as List?)?.cast<String>() ?? const ['*'],
      payload: (map['payload'] as Map?)?.cast<String, Object?>(),
      timeoutMs: (map['timeoutMs'] as num?)?.toInt(),
    );
  }
}

class ControlReplyMessage {
  ControlReplyMessage({
    required this.requestId,
    required this.workerId,
    required this.status,
    Map<String, Object?>? payload,
    this.error,
  }) : payload = payload ?? const {};

  final String requestId;
  final String workerId;
  final String status;
  final Map<String, Object?> payload;
  final Map<String, Object?>? error;

  Map<String, Object?> toMap() => {
        'requestId': requestId,
        'workerId': workerId,
        'status': status,
        'payload': payload,
        if (error != null) 'error': error,
      };

  factory ControlReplyMessage.fromMap(Map<String, Object?> map) {
    return ControlReplyMessage(
      requestId: map['requestId'] as String,
      workerId: map['workerId'] as String,
      status: map['status'] as String,
      payload: (map['payload'] as Map?)?.cast<String, Object?>(),
      error: (map['error'] as Map?)?.cast<String, Object?>(),
    );
  }
}

abstract class ControlQueueNames {
  static String worker(String namespace, String workerId) =>
      '$namespace.control.worker.$workerId';

  static String broadcast(String namespace) => '$namespace.control.broadcast';

  static String reply(String namespace, String requestId) =>
      '$namespace.control.reply.$requestId';
}

class ControlEnvelopeTypes {
  static const command = '__stem.control__';
  static const reply = '__stem.control.reply__';
}

extension ControlCommandEnvelope on ControlCommandMessage {
  Envelope toEnvelope({
    required String queue,
    Map<String, String>? headers,
  }) {
    return Envelope(
      name: ControlEnvelopeTypes.command,
      queue: queue,
      args: toMap(),
      headers: {
        'stem-control': '1',
        if (headers != null) ...headers,
      },
    );
  }
}

extension ControlReplyEnvelope on ControlReplyMessage {
  Envelope toEnvelope({
    required String queue,
    Map<String, String>? headers,
  }) {
    return Envelope(
      name: ControlEnvelopeTypes.reply,
      queue: queue,
      args: toMap(),
      headers: {
        'stem-control-reply': '1',
        if (headers != null) ...headers,
      },
    );
  }
}

ControlReplyMessage controlReplyFromEnvelope(Envelope envelope) {
  return ControlReplyMessage.fromMap(
    envelope.args.map((key, value) => MapEntry(key, value)),
  );
}

ControlCommandMessage controlCommandFromEnvelope(Envelope envelope) {
  return ControlCommandMessage.fromMap(
    envelope.args.map((key, value) => MapEntry(key, value)),
  );
}
