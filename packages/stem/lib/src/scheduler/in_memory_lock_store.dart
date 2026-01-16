import 'dart:async';
import 'dart:math';

import 'package:stem/src/core/contracts.dart';

/// In-memory lock store used for tests and local scheduling.
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
    if (existing != null && !existing.isExpired(now)) {
      return null;
    }
    final resolvedOwner = owner ?? _InMemoryLock.generateOwner();
    final lock = _InMemoryLock(key, resolvedOwner, now.add(ttl), this);
    _locks[key] = lock;
    return lock;
  }

  @override
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

  /// Releases a lock regardless of owner (internal helper).
  void releaseLock(String key) {
    _locks.remove(key);
  }
}

class _InMemoryLock implements Lock {
  _InMemoryLock(this.key, this.owner, this.expiresAt, this.store);

  static String generateOwner() =>
      'owner-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random().nextInt(1 << 32)}';

  @override
  final String key;
  final String owner;
  DateTime expiresAt;
  final InMemoryLockStore store;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);

  @override
  Future<bool> renew(Duration ttl) async {
    expiresAt = DateTime.now().add(ttl);
    return true;
  }

  @override
  Future<void> release() async {
    store.releaseLock(key);
  }
}
