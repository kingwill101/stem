import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';

import 'package:stem/stem.dart';

/// Redis-backed implementation of [RevokeStore].
class RedisRevokeStore implements RevokeStore {
  RedisRevokeStore._(
    this._connection,
    this._command, {
    required this.defaultNamespace,
  });

  final RedisConnection _connection;
  final Command _command;
  final String defaultNamespace;
  bool _closed = false;

  String _recordsKey(String namespace) => '$namespace:control:revokes';

  static Future<RedisRevokeStore> connect(
    String uri, {
    String namespace = 'stem',
    TlsConfig? tls,
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
    final port = parsed.hasPort ? parsed.port : 6379;
    final connection = RedisConnection();
    final scheme = parsed.scheme.isEmpty ? 'redis' : parsed.scheme;
    Command command;
    if (scheme == 'rediss') {
      final securityContext = tls?.toSecurityContext();
      try {
        final socket = await SecureSocket.connect(
          host,
          port,
          context: securityContext,
          onBadCertificate: tls?.allowInsecure == true ? (_) => true : null,
        );
        command = await connection.connectWithSocket(socket);
      } on HandshakeException catch (error, stack) {
        logTlsHandshakeFailure(
          component: 'redis revoke store',
          host: host,
          port: port,
          config: tls,
          error: error,
          stack: stack,
        );
        await connection.close();
        rethrow;
      }
    } else {
      command = await connection.connect(host, port);
    }

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

    return RedisRevokeStore._(connection, command, defaultNamespace: namespace);
  }

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    final raw = await _send(['HGETALL', _recordsKey(namespace)]);
    if (raw is! List || raw.isEmpty) {
      return const [];
    }
    final entries = <RevokeEntry>[];
    for (var i = 0; i < raw.length; i += 2) {
      final value = raw[i + 1] as String;
      final decoded = RevokeEntry.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
      if (decoded.namespace == namespace) {
        entries.add(decoded);
      }
    }
    entries.sort((a, b) => a.version.compareTo(b.version));
    return entries;
  }

  @override
  Future<int> pruneExpired(String namespace, DateTime clock) async {
    final entries = await list(namespace);
    if (entries.isEmpty) return 0;
    final expired = entries.where((entry) => entry.isExpired(clock)).toList();
    if (expired.isEmpty) return 0;
    for (final entry in expired) {
      await _send(['HDEL', _recordsKey(namespace), entry.taskId]);
    }
    return expired.length;
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) async {
    if (entries.isEmpty) return const [];
    final script = '''
local key = KEYS[1]
local taskId = ARGV[1]
local payload = ARGV[2]
local version = tonumber(ARGV[3])
local existing = redis.call("HGET", key, taskId)
if existing then
  local decoded = cjson.decode(existing)
  if tonumber(decoded["version"]) >= version then
    return existing
  end
end
redis.call("HSET", key, taskId, payload)
return payload
''';
    final applied = <RevokeEntry>[];
    for (final entry in entries) {
      final stored = await _send([
        'EVAL',
        script,
        '1',
        _recordsKey(
          entry.namespace.isNotEmpty ? entry.namespace : defaultNamespace,
        ),
        entry.taskId,
        jsonEncode(entry.toJson()),
        entry.version.toString(),
      ]);
      if (stored is String) {
        final decoded = RevokeEntry.fromJson(
          (jsonDecode(stored) as Map).cast<String, Object?>(),
        );
        applied.add(decoded);
      } else {
        applied.add(entry);
      }
    }
    return applied;
  }
}
