import 'dart:async';
import 'dart:io';

import 'package:redis/redis.dart';
import 'package:stem/stem.dart';

/// Factory used to inject a Redis command connection into tests.
typedef RedisRateLimiterCommandFactory =
    Future<({RedisConnection connection, Command command})> Function(
      Uri uri,
      TlsConfig? tls,
    );

/// Redis-backed distributed token-bucket rate limiter.
///
/// [RateLimit.tokens] is the bucket capacity and each successful [acquire]
/// consumes one permit. Refill, consume, and retry calculation happen in one
/// Redis Lua evaluation, so multiple worker processes share one atomic limit.
/// Redis server time is used instead of the Dart process clock.
class RedisRateLimiter implements RateLimiter {
  RedisRateLimiter._(
    this._connection,
    this._command, {
    required this.namespace,
  });

  /// Creates a limiter with injected Redis handles for tests and advanced
  /// connection management.
  factory RedisRateLimiter.test({
    required RedisConnection connection,
    required Command command,
    String namespace = 'stem',
  }) {
    return RedisRateLimiter._(
      connection,
      command,
      namespace: _normalizeNamespace(namespace),
    );
  }

  /// Opens a Redis-backed limiter from [uri].
  ///
  /// `redis://` and `rediss://` URLs are supported. Passwords and database
  /// numbers embedded in the URL are applied before the limiter is returned.
  /// [commandFactory] is intended for tests; production callers should omit
  /// it.
  static Future<RedisRateLimiter> connect(
    String uri, {
    String namespace = 'stem',
    TlsConfig? tls,
    RedisRateLimiterCommandFactory? commandFactory,
  }) async {
    final parsed = Uri.parse(uri);
    final handle = await (commandFactory ?? _defaultCommandFactory)(
      parsed,
      tls,
    );
    final resolvedNamespace = parsed.queryParameters['ns'] ?? namespace;
    return RedisRateLimiter._(
      handle.connection,
      handle.command,
      namespace: _normalizeNamespace(resolvedNamespace),
    );
  }

  /// Atomic refill-and-acquire script.
  ///
  /// The hash stores fractional permits and the last Redis-server timestamp.
  /// A key expires after two windows so inactive limit keys do not accumulate.
  static const String script = '''
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local interval_ms = tonumber(ARGV[2])

local server_time = redis.call('TIME')
local now_ms = tonumber(server_time[1]) * 1000 + math.floor(tonumber(server_time[2]) / 1000)
local stored_tokens = redis.call('HGET', key, 'tokens')
local stored_at = redis.call('HGET', key, 'at')
local available = capacity

if stored_tokens and stored_at then
  local elapsed = math.max(0, now_ms - tonumber(stored_at))
  available = math.min(capacity, tonumber(stored_tokens) + (elapsed * capacity / interval_ms))
end

local allowed = 0
local retry_ms = 0
if available >= 1 then
  available = available - 1
  allowed = 1
else
  retry_ms = math.ceil((1 - available) * interval_ms / capacity)
end

redis.call('HSET', key, 'tokens', available, 'at', now_ms)
redis.call('PEXPIRE', key, math.max(interval_ms * 2, 1000))
return {allowed, retry_ms, available}
''';

  final RedisConnection _connection;
  final Command _command;
  bool _closed = false;

  /// Namespace used to isolate limiter keys.
  final String namespace;

  /// Returns the Redis key used for [key].
  String keyFor(String key) => '$namespace:rate:$key';

  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    if (tokens <= 0) {
      throw ArgumentError.value(tokens, 'tokens', 'Capacity must be positive.');
    }
    final window = interval ?? const Duration(seconds: 1);
    if (window <= Duration.zero) {
      throw ArgumentError.value(
        window,
        'interval',
        'Rate-limit interval must be positive.',
      );
    }
    final intervalMs = window.inMilliseconds;
    if (intervalMs <= 0) {
      throw ArgumentError.value(
        window,
        'interval',
        'Rate-limit interval must be at least one millisecond.',
      );
    }

    final response = await _command.send_object([
      'EVAL',
      script,
      1,
      keyFor(key),
      tokens,
      intervalMs,
    ]);
    if (response is! List || response.length < 3) {
      throw StateError(
        'Unexpected response from Redis rate limiter: $response',
      );
    }

    final allowed = _asInt(response[0]) == 1;
    final retryMs = _asInt(response[1]);
    final remaining = _asDouble(response[2]);
    return RateLimitDecision(
      allowed: allowed,
      retryAfter: allowed || retryMs <= 0
          ? null
          : Duration(milliseconds: retryMs),
      meta: {
        'capacity': tokens,
        'intervalMs': intervalMs,
        'remainingTokens': remaining,
        ...?meta,
      },
    );
  }

  /// Closes the Redis connection owned by this limiter.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }

  static Future<({RedisConnection connection, Command command})>
  _defaultCommandFactory(Uri parsed, TlsConfig? tls) async {
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
          timeout: const Duration(seconds: 5),
        );
        command = await connection.connectWithSocket(socket);
      } on HandshakeException catch (error, stack) {
        logTlsHandshakeFailure(
          component: 'redis rate limiter',
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

    try {
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
    } on Object {
      await connection.close();
      rethrow;
    }
    return (connection: connection, command: command);
  }
}

String _normalizeNamespace(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'stem' : trimmed;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}
