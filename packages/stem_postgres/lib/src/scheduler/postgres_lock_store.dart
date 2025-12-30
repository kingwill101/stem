import 'dart:math';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import '../connection.dart';
import '../database/models/workflow_models.dart';

/// PostgreSQL-backed implementation of [LockStore].
class PostgresLockStore implements LockStore {
  PostgresLockStore._(this._connections);

  final PostgresConnections _connections;
  final Random _random = Random();

  /// Connects to a PostgreSQL database and initializes the locks table.
  ///
  /// The [uri] should be in the format:
  /// `postgresql://username:password@host:port/database`
  static Future<PostgresLockStore> connect(
    String uri, {
    String namespace = 'stem',
    String schema = 'public',
    String? applicationName,
    TlsConfig? tls,
  }) async {
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresLockStore._(connections);
  }

  Future<void> close() async {
    await _connections.close();
  }

  String _owner(String? owner) =>
      owner ??
      'owner-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  @override
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  }) async {
    final ownerValue = _owner(owner);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    final ctx = _connections.context;

    try {
      await ctx.repository<$StemLock>().insert(
        $StemLock(
          key: key,
          owner: ownerValue,
          expiresAt: expiresAt,
          createdAt: now,
        ),
      );
      return _PostgresLock(store: this, key: key, owner: ownerValue);
    } catch (_) {
      // Lock exists, try to clean up expired and retry
      final now = DateTime.now().toUtc();
      final expired = await ctx
          .query<$StemLock>()
          .whereEquals('key', key)
          .where('expiresAt', now, PredicateOperator.lessThan)
          .get();

      for (final lock in expired) {
        await ctx.repository<$StemLock>().delete(lock);
      }

      // Try inserting again
      try {
        await ctx.repository<$StemLock>().insert(
          $StemLock(
            key: key,
            owner: ownerValue,
            expiresAt: expiresAt,
            createdAt: now,
          ),
        );
        return _PostgresLock(store: this, key: key, owner: ownerValue);
      } catch (_) {
        return null;
      }
    }
  }

  Future<bool> _renew(String key, String owner, Duration ttl) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    final ctx = _connections.context;

    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('owner', owner)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .get();

    if (locks.isEmpty) return false;

    final lock = locks.first;
    await ctx.repository<$StemLock>().update(
      lock.copyWith(expiresAt: expiresAt),
    );
    return true;
  }

  Future<bool> _release(String key, String owner) async {
    final ctx = _connections.context;

    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('owner', owner)
        .get();

    if (locks.isEmpty) return false;

    for (final lock in locks) {
      await ctx.repository<$StemLock>().delete(lock);
    }
    return true;
  }

  @override
  Future<String?> ownerOf(String key) async {
    final ctx = _connections.context;
    final now = DateTime.now().toUtc();
    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .get();

    if (locks.isEmpty) return null;
    return locks.first.owner;
  }

  @override
  Future<bool> release(String key, String owner) => _release(key, owner);
}

class _PostgresLock implements Lock {
  _PostgresLock({required this.store, required this.key, required this.owner});

  final PostgresLockStore store;
  @override
  final String key;
  final String owner;

  @override
  Future<bool> renew(Duration ttl) => store._renew(key, owner, ttl);

  @override
  Future<void> release() async {
    await store._release(key, owner);
  }
}
