import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:stem/src/core/contracts.dart' show LockStore, TaskOptions;
import 'package:stem/src/core/envelope.dart';

/// Internal metadata keys stored on envelopes/result backend to track unique tasks.
class UniqueTaskMetadata {
  /// Metadata key storing the computed unique key.
  static const String key = 'stem.unique.key';

  /// Metadata key storing the lock owner.
  static const String owner = 'stem.unique.owner';

  /// Metadata key storing when the unique lock expires.
  static const String expiresAt = 'stem.unique.expiresAt';

  /// Metadata key storing the duplicate count.
  static const String duplicates = 'stem.unique.duplicates';

  /// Metadata key storing an explicit unique key override.
  static const String override = 'stem.unique.override';
}

/// Result of a uniqueness acquisition attempt.
class UniqueTaskClaim {
  /// Creates a claim result for a unique task acquisition attempt.
  UniqueTaskClaim._({
    required this.uniqueKey,
    required this.owner,
    required this.ttl,
    required this.status,
    this.existingTaskId,
  });

  /// Unique key derived from task inputs.
  final String uniqueKey;

  /// Owner associated with the lock (envelope id).
  final String owner;

  /// TTL granted for the lock.
  final Duration ttl;

  /// Claim status.
  final UniqueTaskClaimStatus status;

  /// Existing task id when [status] is [UniqueTaskClaimStatus.duplicate].
  final String? existingTaskId;

  /// Whether this claim represents a newly acquired lock.
  bool get isAcquired => status == UniqueTaskClaimStatus.acquired;

  /// Expiration instant relative to [DateTime.now].
  DateTime computeExpiry(DateTime now) => now.add(ttl);
}

/// Indicates whether uniqueness was acquired or a duplicate was detected.
enum UniqueTaskClaimStatus {
  /// Lock was acquired for this task.
  acquired,

  /// A duplicate task already holds the lock.
  duplicate,
}

/// Clock function used for deterministic testing.
typedef Clock = DateTime Function();

/// Coordinates unique task claims using a [LockStore].
class UniqueTaskCoordinator {
  /// Creates a coordinator that uses the provided [lockStore].
  UniqueTaskCoordinator({
    required this.lockStore,
    Duration defaultTtl = const Duration(minutes: 5),
    String namespace = 'stem:unique',
  }) : defaultTtl = defaultTtl <= Duration.zero
           ? const Duration(seconds: 30)
           : defaultTtl,
       namespace = namespace.isEmpty ? 'stem:unique' : namespace;

  /// Lock store backing unique claims.
  final LockStore lockStore;

  /// Default TTL used when no unique duration is provided.
  final Duration defaultTtl;

  /// Namespace prefix for unique lock keys.
  final String namespace;

  /// Attempts to claim uniqueness for [envelope] using [options].
  Future<UniqueTaskClaim> acquire({
    required Envelope envelope,
    required TaskOptions options,
  }) async {
    final ttl = _resolveTtl(options, envelope);
    final uniqueKey = _resolveUniqueKey(envelope);
    final owner = envelope.id;
    final lockKey = _lockKey(uniqueKey);

    final lock = await lockStore.acquire(lockKey, ttl: ttl, owner: owner);
    if (lock != null) {
      return UniqueTaskClaim._(
        uniqueKey: uniqueKey,
        owner: owner,
        ttl: ttl,
        status: UniqueTaskClaimStatus.acquired,
      );
    }

    final existingOwner = await lockStore.ownerOf(lockKey);
    if (existingOwner == null) {
      // Retry once in case the previous owner expired between calls.
      final retryLock = await lockStore.acquire(
        lockKey,
        ttl: ttl,
        owner: owner,
      );
      if (retryLock != null) {
        return UniqueTaskClaim._(
          uniqueKey: uniqueKey,
          owner: owner,
          ttl: ttl,
          status: UniqueTaskClaimStatus.acquired,
        );
      }
      final retryOwner = await lockStore.ownerOf(lockKey);
      return UniqueTaskClaim._(
        uniqueKey: uniqueKey,
        owner: owner,
        ttl: ttl,
        status: UniqueTaskClaimStatus.duplicate,
        existingTaskId: retryOwner,
      );
    }

    return UniqueTaskClaim._(
      uniqueKey: uniqueKey,
      owner: owner,
      ttl: ttl,
      status: UniqueTaskClaimStatus.duplicate,
      existingTaskId: existingOwner,
    );
  }

  /// Releases the uniqueness lock associated with [uniqueKey] and [owner].
  Future<bool> release(String uniqueKey, String owner) async {
    return lockStore.release(_lockKey(uniqueKey), owner);
  }

  /// Resolves the lock TTL from options, envelope overrides, or defaults.
  Duration _resolveTtl(TaskOptions options, Envelope envelope) {
    final ttl =
        options.uniqueFor ??
        options.visibilityTimeout ??
        envelope.visibilityTimeout ??
        defaultTtl;
    if (ttl <= Duration.zero) {
      return defaultTtl;
    }
    return ttl;
  }

  String _lockKey(String uniqueKey) => '$namespace:$uniqueKey';

  /// Builds or extracts the unique key used for lock ownership.
  String _resolveUniqueKey(Envelope envelope) {
    final meta = envelope.meta;
    final override = meta[UniqueTaskMetadata.override];
    if (override is String && override.isNotEmpty) {
      return override;
    }
    final explicit = meta['uniqueKey'];
    if (explicit is String && explicit.isNotEmpty) {
      return explicit;
    }

    final payload = <String, Object?>{
      'task': envelope.name,
      'queue': envelope.queue,
      'args': _canonicalize(envelope.args),
      'headers': _canonicalize(envelope.headers),
      'meta': _canonicalize(_filterMeta(meta)),
    };
    final canonical = jsonEncode(payload);
    final digest = sha256.convert(utf8.encode(canonical));
    return digest.toString();
  }

  /// Filters metadata used in unique-key hashing.
  Map<String, Object?> _filterMeta(Map<String, Object?> meta) {
    final filtered = <String, Object?>{};
    meta.forEach((key, value) {
      if (key.startsWith('stem.')) return;
      filtered[key] = value;
    });
    return filtered;
  }

  /// Canonicalizes values to stable JSON for hashing.
  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      return {
        for (final entry in entries) entry.key: _canonicalize(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value;
  }
}
