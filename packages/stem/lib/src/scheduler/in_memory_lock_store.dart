import 'dart:async';

import '../core/contracts.dart';

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
    final lock = _InMemoryLock(key, now.add(ttl), this);
    _locks[key] = lock;
    return lock;
  }

  void releaseLock(String key) {
    _locks.remove(key);
  }
}

class _InMemoryLock implements Lock {
  _InMemoryLock(this.key, this.expiresAt, this.store);

  @override
  final String key;
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
