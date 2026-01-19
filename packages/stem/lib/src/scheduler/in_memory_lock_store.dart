/// Volatile, in-memory implementation of a lock store.
///
/// This library provides [InMemoryLockStore], which is primarily intended for
/// unit testing or single-process local development. It does not provide
/// cross-process or cross-machine exclusion.
library;

import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:uuid/uuid.dart';

/// In-memory lock store used for tests and local scheduling.
///
/// Implements a simple TTL-based mutex map. Each key is associated with
/// an owner and an expiration timestamp.
class InMemoryLockStore implements LockStore {
  final Map<String, _InMemoryLock> _locks = {};

  @override
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  }) async {
    final now = DateTime.now();
    final existing = _locks[key];

    // Check if a non-expired lock already exists for this key.
    if (existing != null && !existing.isExpired(now)) {
      return null;
    }

    final resolvedOwner = owner ?? _InMemoryLock.generateOwner();
    final lock = _InMemoryLock(key, resolvedOwner, now.add(ttl), this);
    _locks[key] = lock;
    return lock;
  }

  @override
  /// Returns the owner of the lock if it exists and has not expired.
  Future<String?> ownerOf(String key) async {
    final lock = _locks[key];
    if (lock == null) return null;
    if (lock.isExpired(DateTime.now())) {
      _locks.remove(key);
      return null;
    }
    return lock.owner;
  }

  @override
  /// Extends the lock TTL when the [owner] still holds it.
  Future<bool> renew(String key, String owner, Duration ttl) async {
    final lock = _locks[key];
    if (lock == null) {
      return false;
    }
    if (lock.owner != owner) {
      return false;
    }
    if (lock.isExpired(DateTime.now())) {
      _locks.remove(key);
      return false;
    }
    lock.expiresAt = DateTime.now().add(ttl);
    return true;
  }

  @override
  /// Releases the lock if the requesting [owner] matches.
  Future<bool> release(String key, String owner) async {
    final lock = _locks[key];
    if (lock == null) {
      return false;
    }
    if (lock.owner != owner) {
      return false;
    }
    _locks.remove(key);
    return true;
  }

  /// Internal helper to release a lock by key, bypassing owner checks.
  ///
  /// Usually called via [_InMemoryLock.release].
  void releaseLock(String key) {
    _locks.remove(key);
  }
}

/// Internal representation of an active or expired memory lock.
class _InMemoryLock implements Lock {
  _InMemoryLock(this.key, this.owner, this.expiresAt, this.store);

  /// Generates a unique owner identifier using UUID v7.
  static String generateOwner() => const Uuid().v7();

  @override
  final String key;

  /// The unique identifier that "holds" this lock.
  @override
  final String owner;

  /// The absolute point in time when this lock will automatically expire.
  DateTime expiresAt;

  /// The store that created this lock.
  final InMemoryLockStore store;

  /// Checks if the lock is expired relative to [now].
  bool isExpired(DateTime now) => now.isAfter(expiresAt);

  @override
  /// Extends this in-memory lock's expiration timestamp.
  Future<bool> renew(Duration ttl) async {
    expiresAt = DateTime.now().add(ttl);
    return true;
  }

  @override
  /// Releases this lock through the parent store.
  Future<void> release() async {
    store.releaseLock(key);
  }
}
