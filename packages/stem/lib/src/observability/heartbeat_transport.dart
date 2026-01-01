import 'dart:async';
import 'package:stem/src/observability/heartbeat.dart';

/// Transport abstraction for distributing worker heartbeat payloads.
abstract class HeartbeatTransport {
  /// Creates a heartbeat transport implementation.
  const HeartbeatTransport();

  /// Publish the [heartbeat] to the underlying channel.
  Future<void> publish(WorkerHeartbeat heartbeat);

  /// Release any held resources.
  Future<void> close();
}

/// Transport that intentionally drops all heartbeats.
class NoopHeartbeatTransport extends HeartbeatTransport {
  /// Creates a transport that drops all heartbeats.
  const NoopHeartbeatTransport();

  /// Intentionally drops the provided [heartbeat].
  @override
  Future<void> publish(WorkerHeartbeat heartbeat) async {}

  /// Nothing to close for the noop transport.
  @override
  Future<void> close() async {}
}
