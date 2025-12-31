import 'dart:io';
import 'dart:math';

import 'package:redis/redis.dart';

import 'package:stem/stem.dart';

/// Redis-backed implementation of [LockStore].
class RedisLockStore implements LockStore {
  RedisLockStore._(this._connection, this._command, {this.namespace = 'stem'})
    : _random = Random();

  final RedisConnection _connection;
  final Command _command;

  /// Namespace used to scope lock keys.
  final String namespace;
  final Random _random;
  bool _closed = false;

  /// Connects to Redis and returns a lock store instance.
  static Future<RedisLockStore> connect(
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
          onBadCertificate: tls?.allowInsecure ?? false ? (_) => true : null,
        );
        command = await connection.connectWithSocket(socket);
      } on HandshakeException catch (error, stack) {
        logTlsHandshakeFailure(
          component: 'redis lock store',
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

    return RedisLockStore._(connection, command, namespace: namespace);
  }

  /// Closes the lock store and releases Redis resources.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }

  String _key(String key) => '$namespace:lock:$key';
  String _owner(String? owner) =>
      owner ??
      'owner-${DateTime.now().microsecondsSinceEpoch}-'
          '${_random.nextInt(1 << 32)}';

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  @override
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  }) async {
    final redisKey = _key(key);
    final value = _owner(owner);
    final result = await _send([
      'SET',
      redisKey,
      value,
      'NX',
      'PX',
      ttl.inMilliseconds.toString(),
    ]);
    if (result != 'OK') {
      return null;
    }
    return _RedisLock(store: this, key: key, redisKey: redisKey, owner: value);
  }

  Future<bool> _renew(String redisKey, String owner, Duration ttl) async {
    const script = '''
if redis.call("GET", KEYS[1]) == ARGV[1] then
  return redis.call("PEXPIRE", KEYS[1], ARGV[2])
else
  return 0
end
''';
    final result = await _send([
      'EVAL',
      script,
      '1',
      redisKey,
      owner,
      ttl.inMilliseconds.toString(),
    ]);
    return result == 1;
  }

  Future<bool> _release(String redisKey, String owner) async {
    const script = '''
if redis.call("GET", KEYS[1]) == ARGV[1] then
  return redis.call("DEL", KEYS[1])
else
  return 0
end
''';
    final result = await _send(['EVAL', script, '1', redisKey, owner]);
    return result == 1;
  }

  @override
  Future<String?> ownerOf(String key) async {
    final result = await _send(['GET', _key(key)]);
    return result is String ? result : result?.toString();
  }

  @override
  Future<bool> release(String key, String owner) => _release(_key(key), owner);
}

class _RedisLock implements Lock {
  _RedisLock({
    required this.store,
    required this.key,
    required this.redisKey,
    required this.owner,
  });

  final RedisLockStore store;
  @override
  final String key;
  final String redisKey;
  final String owner;

  @override
  Future<bool> renew(Duration ttl) => store._renew(redisKey, owner, ttl);

  @override
  Future<void> release() async {
    await store._release(redisKey, owner);
  }
}
