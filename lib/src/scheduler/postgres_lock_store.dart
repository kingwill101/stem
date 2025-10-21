import 'dart:math';

import 'package:postgres/postgres.dart';

import '../core/contracts.dart';
import '../postgres/postgres_client.dart';

/// PostgreSQL-backed implementation of [LockStore].
class PostgresLockStore implements LockStore {
  PostgresLockStore._(
    this._client, {
    this.namespace = 'stem',
    this.schema = 'public',
  }) : _random = Random();

  final PostgresClient _client;
  final String namespace;
  final String schema;
  final Random _random;
  bool _closed = false;

  /// Connects to a PostgreSQL database and initializes the locks table.
  ///
  /// The [uri] should be in the format:
  /// `postgresql://username:password@host:port/database`
  static Future<PostgresLockStore> connect(
    String uri, {
    String namespace = 'stem',
    String schema = 'public',
    String? applicationName,
  }) async {
    final client = PostgresClient(uri, applicationName: applicationName);
    final store = PostgresLockStore._(
      client,
      namespace: namespace,
      schema: schema,
    );
    await store._initializeTables();
    return store;
  }

  /// Initializes the database schema with the locks table.
  Future<void> _initializeTables() async {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    await _client.run((conn) async {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $schema.${prefix}locks (
          key TEXT PRIMARY KEY,
          owner TEXT NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await conn.execute('''
        CREATE INDEX IF NOT EXISTS ${prefix}locks_expires_at_idx
        ON $schema.${prefix}locks(expires_at)
      ''');

      // Clean up expired locks periodically (this can be a background job)
      await conn.execute('''
        DELETE FROM $schema.${prefix}locks
        WHERE expires_at < NOW()
      ''');
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.close();
  }

  String _tableName() {
    final prefix = namespace.isNotEmpty ? '${namespace}_' : '';
    return '$schema.${prefix}locks';
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
    final expiresAt = DateTime.now().add(ttl);

    return _client.run((conn) async {
      // Try to insert a new lock
      try {
        await conn.execute(
          Sql.named('''
          INSERT INTO ${_tableName()} (key, owner, expires_at)
          VALUES (@key, @owner, @expires_at)
          '''),
          parameters: {
            'key': key,
            'owner': ownerValue,
            'expires_at': expiresAt,
          },
        );
        return _PostgresLock(store: this, key: key, owner: ownerValue);
      } catch (_) {
        // Lock already exists or expired, try to clean up and acquire
        final deleted = await conn.execute(
          Sql.named('''
          DELETE FROM ${_tableName()}
          WHERE key = @key AND expires_at < NOW()
          '''),
          parameters: {'key': key},
        );

        if (deleted.affectedRows > 0) {
          // Try again after cleanup
          try {
            await conn.execute(
              Sql.named('''
              INSERT INTO ${_tableName()} (key, owner, expires_at)
              VALUES (@key, @owner, @expires_at)
              '''),
              parameters: {
                'key': key,
                'owner': ownerValue,
                'expires_at': expiresAt,
              },
            );
            return _PostgresLock(store: this, key: key, owner: ownerValue);
          } catch (_) {
            return null;
          }
        }
        return null;
      }
    });
  }

  Future<bool> _renew(String key, String owner, Duration ttl) async {
    final expiresAt = DateTime.now().add(ttl);

    return _client.run((conn) async {
      final result = await conn.execute(
        Sql.named('''
        UPDATE ${_tableName()}
        SET expires_at = @expires_at
        WHERE key = @key AND owner = @owner AND expires_at > NOW()
        '''),
        parameters: {'key': key, 'owner': owner, 'expires_at': expiresAt},
      );
      return result.affectedRows > 0;
    });
  }

  Future<void> _release(String key, String owner) async {
    await _client.run((conn) async {
      await conn.execute(
        Sql.named('''
        DELETE FROM ${_tableName()}
        WHERE key = @key AND owner = @owner
        '''),
        parameters: {'key': key, 'owner': owner},
      );
    });
  }
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
  Future<void> release() => store._release(key, owner);
}
