import 'dart:async';

import 'package:redis/redis.dart';

import 'heartbeat.dart';

/// Transport abstraction for distributing worker heartbeat payloads.
abstract class HeartbeatTransport {
  const HeartbeatTransport();

  /// Publish the [heartbeat] to the underlying channel.
  Future<void> publish(WorkerHeartbeat heartbeat);

  /// Release any held resources.
  Future<void> close();
}

/// Transport that intentionally drops all heartbeats.
class NoopHeartbeatTransport extends HeartbeatTransport {
  const NoopHeartbeatTransport();

  /// Intentionally drops the provided [heartbeat].
  @override
  Future<void> publish(WorkerHeartbeat heartbeat) async {}

  /// Nothing to close for the noop transport.
  @override
  Future<void> close() async {}
}

/// Redis-backed transport that publishes encoded heartbeats to a channel.
class RedisHeartbeatTransport extends HeartbeatTransport {
  /// Creates an instance using an established [_connection], [Command], and
  /// target [_channel].
  RedisHeartbeatTransport._(this._connection, this._command, this._channel);

  /// Connection used to communicate with Redis.
  final RedisConnection _connection;

  /// Command interface used for issuing Redis operations.
  final Command _command;

  /// Target Redis pub/sub channel for encoded heartbeats.
  final String _channel;

  /// Opens a connection to the Redis instance defined by [uri].
  ///
  /// If a password or database index is embedded in [uri], the connection is
  /// authenticated and selected automatically. Heartbeats are published to the
  /// namespace-specific channel.
  static Future<RedisHeartbeatTransport> connect(
    String uri, {
    String namespace = 'stem',
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
    final port = parsed.hasPort ? parsed.port : 6379;
    final connection = RedisConnection();
    final command = await connection.connect(host, port);

    if (parsed.userInfo.isNotEmpty) {
      final parts = parsed.userInfo.split(':');
      final password = parts.length == 2 ? parts[1] : parts[0];
      await command.send_object(['AUTH', password]);
    }

    if (parsed.pathSegments.isNotEmpty) {
      final db = int.tryParse(parsed.pathSegments.first);
      if (db != null) {
        await command.send_object(['SELECT', db]);
      }
    }

    return RedisHeartbeatTransport._(
      connection,
      command,
      WorkerHeartbeat.topic(namespace),
    );
  }

  /// Publishes the encoded [heartbeat] to the configured Redis channel.
  @override
  Future<void> publish(WorkerHeartbeat heartbeat) async {
    await _command.send_object(['PUBLISH', _channel, heartbeat.encode()]);
  }

  /// Closes the Redis connection.
  @override
  Future<void> close() async {
    await _connection.close();
  }
}
