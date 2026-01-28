import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/workflow_models.dart';
import 'package:uuid/uuid.dart';

/// PostgreSQL-backed implementation of [LockStore].
class PostgresLockStore implements LockStore {
  /// Creates a lock store backed by PostgreSQL.
  PostgresLockStore._(this._connections, {required this.namespace});

  /// Creates a lock store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<PostgresLockStore> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    bool runMigrations = true,
  }) async {
    final resolvedNamespace = namespace.trim().isNotEmpty
        ? namespace.trim()
        : 'stem';
    final connections = await PostgresConnections.openWithDataSource(
      dataSource,
      runMigrations: runMigrations,
    );
    return PostgresLockStore._(connections, namespace: resolvedNamespace);
  }

  /// Namespace used to scope lock records.
  final String namespace;
  final PostgresConnections _connections;

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
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresLockStore._(
      connections,
      namespace: resolvedNamespace,
    );
  }

  /// Closes the lock store and releases any database resources.
  Future<void> close() async {
    await _connections.close();
  }

  String _owner(String? owner) => owner ?? const Uuid().v7();

  /// Attempts to acquire a lock for the provided [key].
  ///
  /// Returns a [_PostgresLock] handle when successful or `null` if the lock is
  /// currently held by another owner.
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
    final repository = ctx.repository<$StemLock>();

    final inserted = await repository.insertOrIgnore(
      $StemLock(
        key: key,
        namespace: namespace,
        owner: ownerValue,
        expiresAt: expiresAt,
        createdAt: now,
      ),
    );
    if (inserted > 0) {
      return _PostgresLock(store: this, key: key, owner: ownerValue);
    }

    // Lock exists, try to clean up expired and retry.
    final expired = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.lessThan)
        .get();

    for (final lock in expired) {
      await repository.delete(lock);
    }

    final retryInserted = await repository.insertOrIgnore(
      $StemLock(
        key: key,
        namespace: namespace,
        owner: ownerValue,
        expiresAt: expiresAt,
        createdAt: now,
      ),
    );
    if (retryInserted > 0) {
      return _PostgresLock(store: this, key: key, owner: ownerValue);
    }
    return null;
  }

  Future<bool> _renew(String key, String owner, Duration ttl) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    final ctx = _connections.context;

    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('owner', owner)
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .get();

    if (locks.isEmpty) return false;

    final lock = locks.first;
    await ctx.repository<$StemLock>().update(
      lock.copyWith(expiresAt: expiresAt),
    );
    return true;
  }

  /// Renews the lock for [key] when held by [owner].
  @override
  Future<bool> renew(String key, String owner, Duration ttl) =>
      _renew(key, owner, ttl);

  Future<bool> _release(String key, String owner) async {
    final ctx = _connections.context;

    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('owner', owner)
        .whereEquals('namespace', namespace)
        .get();

    if (locks.isEmpty) return false;

    for (final lock in locks) {
      await ctx.repository<$StemLock>().delete(lock);
    }
    return true;
  }

  /// Returns the current owner for the given [key] if the lock is active.
  @override
  Future<String?> ownerOf(String key) async {
    final ctx = _connections.context;
    final now = DateTime.now().toUtc();
    final locks = await ctx
        .query<$StemLock>()
        .whereEquals('key', key)
        .whereEquals('namespace', namespace)
        .where('expiresAt', now, PredicateOperator.greaterThan)
        .get();

    if (locks.isEmpty) return null;
    return locks.first.owner;
  }

  /// Releases the lock for [key] when held by [owner].
  @override
  Future<bool> release(String key, String owner) => _release(key, owner);
}

class _PostgresLock implements Lock {
  _PostgresLock({required this.store, required this.key, required this.owner});

  final PostgresLockStore store;
  @override
  final String key;
  @override
  final String owner;

  @override
  Future<bool> renew(Duration ttl) => store._renew(key, owner, ttl);

  @override
  Future<void> release() async {
    await store._release(key, owner);
  }
}
