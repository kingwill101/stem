import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';

/// PostgreSQL-backed distributed token-bucket rate limiter.
///
/// Each acquire runs in a database transaction and locks one bucket row with
/// `FOR UPDATE`. This makes refill and consumption atomic across processes and
/// avoids relying on the wall clock of any individual worker. The bucket
/// stores micro-permits as integers so fractional refills do not accumulate
/// floating-point error.
class PostgresRateLimiter implements RateLimiter {
  PostgresRateLimiter._(this._connections, {required this.namespace});

  /// Creates a limiter using an existing initialized [DataSource].
  ///
  /// The caller remains responsible for disposing [dataSource].
  static Future<PostgresRateLimiter> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    bool runMigrations = true,
  }) async {
    final connections = await PostgresConnections.openWithDataSource(
      dataSource,
      runMigrations: runMigrations,
    );
    return PostgresRateLimiter._(
      connections,
      namespace: _normalizeNamespace(namespace),
    );
  }

  /// Opens a limiter from a PostgreSQL connection string and runs migrations.
  static Future<PostgresRateLimiter> connect(
    String uri, {
    String namespace = 'stem',
  }) async {
    final connections = await PostgresConnections.open(
      connectionString: uri,
    );
    return PostgresRateLimiter._(
      connections,
      namespace: _normalizeNamespace(namespace),
    );
  }

  static const int _microsPerPermit = 1000000;
  static const int _maxCapacity = 9000000000000;

  final PostgresConnections _connections;

  /// Namespace used to isolate limiter buckets.
  final String namespace;

  /// Closes the owned connection when the limiter was created with [connect].
  Future<void> close() => _connections.close();

  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    if (tokens <= 0 || tokens > _maxCapacity) {
      throw ArgumentError.value(
        tokens,
        'tokens',
        'Capacity must be between 1 and $_maxCapacity.',
      );
    }
    final window = interval ?? const Duration(seconds: 1);
    final intervalMs = window.inMilliseconds;
    if (intervalMs <= 0) {
      throw ArgumentError.value(
        window,
        'interval',
        'Rate-limit interval must be at least one millisecond.',
      );
    }

    final capacityMicros = tokens * _microsPerPermit;
    return _connections.runInTransaction((context) async {
      final driver = context.driver;
      final nowRows = await driver.queryRaw(
        'SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::bigint '
        'AS now_ms',
      );
      final nowMs = _asInt(nowRows.single['now_ms']);

      // Insert first so concurrent first-use callers serialize on the primary
      // key. ON CONFLICT waits for the competing transaction, then the row is
      // selected and locked below.
      await driver.executeRaw(
        '''
INSERT INTO stem_rate_limit_buckets
  (namespace, rate_key, capacity, interval_ms, available_micros,
   updated_at_ms, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, clock_timestamp(), clock_timestamp())
ON CONFLICT (namespace, rate_key) DO NOTHING
''',
        [
          namespace,
          key,
          tokens,
          intervalMs,
          capacityMicros,
          nowMs,
        ],
      );

      final rows = await driver.queryRaw(
        '''
SELECT capacity, interval_ms, available_micros, updated_at_ms
FROM stem_rate_limit_buckets
WHERE namespace = ? AND rate_key = ?
FOR UPDATE
''',
        [namespace, key],
      );
      if (rows.isEmpty) {
        throw StateError('Rate-limit bucket was not created: $namespace/$key');
      }

      final row = rows.single;
      final storedCapacity = _asInt(row['capacity']);
      final storedInterval = _asInt(row['interval_ms']);
      final storedAvailable = _asInt(row['available_micros']);
      final storedAt = _asInt(row['updated_at_ms']);
      final capacityChanged =
          storedCapacity != tokens || storedInterval != intervalMs;

      final available = capacityChanged
          ? capacityMicros
          : _refill(
              availableMicros: storedAvailable,
              capacityMicros: capacityMicros,
              elapsedMs: (nowMs - storedAt).clamp(0, nowMs),
              intervalMs: intervalMs,
            );
      final allowed = available >= _microsPerPermit;
      final remaining = allowed ? available - _microsPerPermit : available;
      final retryAfterMs = allowed
          ? null
          : _retryAfterMs(
              missingMicros: _microsPerPermit - available,
              capacityMicros: capacityMicros,
              intervalMs: intervalMs,
            );

      await driver.executeRaw(
        '''
UPDATE stem_rate_limit_buckets
SET capacity = ?, interval_ms = ?, available_micros = ?,
    updated_at_ms = ?, updated_at = clock_timestamp()
WHERE namespace = ? AND rate_key = ?
''',
        [
          tokens,
          intervalMs,
          remaining,
          nowMs,
          namespace,
          key,
        ],
      );

      return RateLimitDecision(
        allowed: allowed,
        retryAfter: retryAfterMs == null
            ? null
            : Duration(milliseconds: retryAfterMs),
        meta: {
          'capacity': tokens,
          'intervalMs': intervalMs,
          'remainingTokens': remaining / _microsPerPermit,
          'backend': 'postgres',
          ...?meta,
        },
      );
    });
  }

  static int _refill({
    required int availableMicros,
    required int capacityMicros,
    required int elapsedMs,
    required int intervalMs,
  }) {
    if (elapsedMs <= 0) return availableMicros.clamp(0, capacityMicros);
    final added =
        (BigInt.from(elapsedMs) * BigInt.from(capacityMicros)) ~/
        BigInt.from(intervalMs);
    final total = BigInt.from(availableMicros) + added;
    final capped = total.compareTo(BigInt.from(capacityMicros)) > 0
        ? BigInt.from(capacityMicros)
        : total;
    return capped.toInt();
  }

  static int _retryAfterMs({
    required int missingMicros,
    required int capacityMicros,
    required int intervalMs,
  }) {
    final numerator = BigInt.from(missingMicros) * BigInt.from(intervalMs);
    final denominator = BigInt.from(capacityMicros);
    final milliseconds = (numerator + denominator - BigInt.one) ~/ denominator;
    return milliseconds < BigInt.one ? 1 : milliseconds.toInt();
  }
}

String _normalizeNamespace(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'stem' : trimmed;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}
