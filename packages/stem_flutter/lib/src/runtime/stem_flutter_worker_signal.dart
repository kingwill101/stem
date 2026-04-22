import 'dart:isolate';

/// Lifecycle state exposed by Flutter-hosted worker integrations.
enum StemFlutterWorkerStatus {
  /// Worker isolate is still bootstrapping.
  starting,

  /// Worker is healthy and heartbeats are fresh.
  running,

  /// Worker started but heartbeats are stale.
  waiting,

  /// Worker encountered a fatal startup or runtime error.
  error,

  /// Worker isolate has exited.
  stopped,
}

/// Envelope type exchanged between worker isolates and the UI isolate.
enum StemFlutterWorkerSignalType {
  /// Worker boot completed and its command port is available.
  ready,

  /// Worker lifecycle status update.
  status,

  /// Non-fatal warning emitted by the worker.
  warning,

  /// Fatal worker error.
  fatal,
}

/// Serializable worker signal used by Flutter-hosted runtimes.
///
/// Signals are exchanged between the worker isolate and the UI isolate using
/// isolate-safe message payloads.
class StemFlutterWorkerSignal {
  const StemFlutterWorkerSignal._({
    required this.type,
    this.status,
    this.detail,
    this.message,
    this.commandPort,
  });

  /// Emits a ready signal with an optional [commandPort].
  const StemFlutterWorkerSignal.ready({SendPort? commandPort, String? detail})
    : this._(
        type: StemFlutterWorkerSignalType.ready,
        commandPort: commandPort,
        detail: detail,
      );

  /// Emits a worker [status] update.
  const StemFlutterWorkerSignal.status({
    required StemFlutterWorkerStatus status,
    String? detail,
  }) : this._(
         type: StemFlutterWorkerSignalType.status,
         status: status,
         detail: detail,
       );

  /// Emits a non-fatal warning.
  const StemFlutterWorkerSignal.warning(String message)
    : this._(type: StemFlutterWorkerSignalType.warning, message: message);

  /// Emits a fatal error.
  const StemFlutterWorkerSignal.fatal(String message)
    : this._(type: StemFlutterWorkerSignalType.fatal, message: message);

  /// The signal type.
  final StemFlutterWorkerSignalType type;

  /// The worker state carried by status updates.
  final StemFlutterWorkerStatus? status;

  /// The optional detail string for ready and status updates.
  final String? detail;

  /// The warning or fatal message payload.
  final String? message;

  /// The command port exposed by the worker.
  final SendPort? commandPort;

  /// Converts this signal into an isolate-safe message map.
  Map<String, Object?> toMessage() => switch (type) {
    StemFlutterWorkerSignalType.ready => <String, Object?>{
      'type': 'ready',
      if (commandPort != null) 'sendPort': commandPort,
      if (detail != null) 'detail': detail,
    },
    StemFlutterWorkerSignalType.status => <String, Object?>{
      'type': 'status',
      'state': status!.name,
      if (detail != null) 'detail': detail,
    },
    StemFlutterWorkerSignalType.warning => <String, Object?>{
      'type': 'warning',
      'warning': message,
    },
    StemFlutterWorkerSignalType.fatal => <String, Object?>{
      'type': 'fatal',
      'fatal': message,
    },
  };

  /// Parses an isolate message into a strongly typed worker signal.
  static StemFlutterWorkerSignal? tryParse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final type = raw['type']?.toString();
    return switch (type) {
      'ready' => StemFlutterWorkerSignal.ready(
        commandPort: raw['sendPort'] as SendPort?,
        detail: raw['detail']?.toString(),
      ),
      'status' => _parseStatusSignal(raw),
      'warning' => StemFlutterWorkerSignal.warning(
        raw['warning']?.toString() ?? 'warning',
      ),
      'fatal' || 'error' => StemFlutterWorkerSignal.fatal(
        raw['fatal']?.toString() ?? raw['error']?.toString() ?? 'error',
      ),
      _ => null,
    };
  }
}

StemFlutterWorkerSignal? _parseStatusSignal(Map<Object?, Object?> raw) {
  final rawState = raw['state']?.toString();
  final status = switch (rawState) {
    null => StemFlutterWorkerStatus.starting,
    final String value => _workerStatusByName(value),
  };
  if (status == null) {
    return null;
  }
  return StemFlutterWorkerSignal.status(
    status: status,
    detail: raw['detail']?.toString(),
  );
}

StemFlutterWorkerStatus? _workerStatusByName(String name) {
  for (final status in StemFlutterWorkerStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return null;
}
