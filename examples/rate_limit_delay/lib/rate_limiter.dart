import 'dart:async';
import 'dart:io';

import 'package:redis/redis.dart';
import 'package:stem/stem.dart';

/// Simple fixed-window rate limiter backed by Redis.
///
/// This is intentionally lightweight for demo purposes. Production deployments
/// should use a more robust implementation with Lua scripts cached server-side
/// and better error handling.
class RedisFixedWindowRateLimiter implements RateLimiter {
  RedisFixedWindowRateLimiter._(
    this._connection,
    this._command, {
    required this.namespace,
  });

  final RedisConnection _connection;
  final Command _command;
  final String namespace;
  bool _closed = false;

  static const _script = '''
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local interval = tonumber(ARGV[2])

local current = redis.call('GET', key)
if not current then
  redis.call('SET', key, 1, 'PX', interval)
  return {1, interval}
end

current = tonumber(current)
if current < limit then
  redis.call('INCR', key)
  local ttl = redis.call('PTTL', key)
  if ttl < 0 then ttl = interval end
  return {1, ttl}
end

local ttl = redis.call('PTTL', key)
if ttl < 0 then ttl = interval end
return {0, ttl}
''';

  static Future<RedisFixedWindowRateLimiter> connect(
    String uri, {
    String namespace = 'stem-demo',
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
    final port = parsed.hasPort ? parsed.port : 6379;
    final connection = RedisConnection();
    final scheme = parsed.scheme.isEmpty ? 'redis' : parsed.scheme;

    if (scheme == 'rediss') {
      throw UnsupportedError(
        'TLS connections are not implemented for the rate limiter demo. '
        'Use redis:// URLs or extend the example.',
      );
    }

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

    final resolvedNamespace =
        parsed.queryParameters['ns'] ?? namespace.trim();

    return RedisFixedWindowRateLimiter._(
      connection,
      command,
      namespace: resolvedNamespace.isEmpty ? 'stem-demo' : resolvedNamespace,
    );
  }

  String _keyFor(String key) => '$namespace:rate:$key';

  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    final window = interval ?? const Duration(seconds: 1);
    final response = await _command.send_object([
      'EVAL',
      _script,
      1,
      _keyFor(key),
      tokens,
      window.inMilliseconds,
    ]);

    if (response is! List || response.length != 2) {
      throw StateError(
        'Unexpected response from rate limiter script: $response',
      );
    }

    final allowed = (response[0] as num).toInt() == 1;
    final ttlMs = (response[1] as num).toInt();
    final remainingMs = ttlMs < 0 ? window.inMilliseconds : ttlMs;
    final retryAfter =
        allowed ? null : Duration(milliseconds: remainingMs);

    final decision = RateLimitDecision(
      allowed: allowed,
      retryAfter: retryAfter,
      meta: {
        'windowMs': window.inMilliseconds,
        'remainingMs': remainingMs,
        if (meta != null) ...meta,
      },
    );

    final status = allowed ? 'granted' : 'denied';
    final retryText =
        retryAfter == null ? 'available immediately' : 'retry in ${retryAfter.inMilliseconds}ms';
    stdout.writeln(
      '[rate-limiter][$status] key=$key tokens=$tokens window=${window.inMilliseconds}ms -> $retryText',
    );

    return decision;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }
}
