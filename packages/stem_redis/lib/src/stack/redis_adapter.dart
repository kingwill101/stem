import 'package:stem/stem.dart';
import 'package:stem_redis/src/control/redis_revoke_store.dart';
import 'package:stem_redis/src/scheduler/redis_lock_store.dart';
import 'package:stem_redis/src/scheduler/redis_schedule_store.dart';
import 'package:stem_redis/src/workflow/redis_factories.dart';

/// Creates a [ScheduleStoreFactory] backed by Redis.
ScheduleStoreFactory redisScheduleStoreFactory(
  String uri, {
  String namespace = 'stem',
  Duration lockTtl = const Duration(seconds: 5),
  ScheduleCalculator? calculator,
  TlsConfig? tls,
}) {
  return ScheduleStoreFactory(
    create: () async => RedisScheduleStore.connect(
      uri,
      namespace: namespace,
      lockTtl: lockTtl,
      calculator: calculator,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is RedisScheduleStore) {
        await store.close();
      }
    },
  );
}

/// Creates a [LockStoreFactory] backed by Redis.
LockStoreFactory redisLockStoreFactory(
  String uri, {
  String namespace = 'stem',
  TlsConfig? tls,
}) {
  return LockStoreFactory(
    create: () async => RedisLockStore.connect(
      uri,
      namespace: namespace,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is RedisLockStore) {
        await store.close();
      }
    },
  );
}

/// Creates a [RevokeStoreFactory] backed by Redis.
RevokeStoreFactory redisRevokeStoreFactory(
  String uri, {
  String namespace = 'stem',
  TlsConfig? tls,
}) {
  return RevokeStoreFactory(
    create: () async => RedisRevokeStore.connect(
      uri,
      namespace: namespace,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is RedisRevokeStore) {
        await store.close();
      }
    },
  );
}

/// Adapter that resolves Redis-backed factories from a `redis://` URL.
class StemRedisAdapter implements StemStoreAdapter {
  /// Creates a Redis adapter with optional defaults.
  const StemRedisAdapter({
    this.namespace = 'stem',
    this.tls,
    this.scheduleLockTtl = const Duration(seconds: 5),
    this.scheduleCalculator,
  });

  /// Namespace prefix used by Redis-backed stores.
  final String namespace;

  /// Optional TLS configuration shared by Redis clients.
  final TlsConfig? tls;

  /// TTL used by the schedule store for entry locks.
  final Duration scheduleLockTtl;

  /// Optional calculator override for schedule stores.
  final ScheduleCalculator? scheduleCalculator;

  @override
  String get name => 'stem_redis';

  @override
  bool supports(Uri uri, StemStoreKind kind) {
    return uri.scheme == 'redis' || uri.scheme == 'rediss';
  }

  @override
  StemBrokerFactory? brokerFactory(Uri uri) {
    return redisBrokerFactory(
      uri.toString(),
      namespace: namespace,
      tls: tls,
    );
  }

  @override
  StemBackendFactory? backendFactory(Uri uri) {
    return redisResultBackendFactory(
      uri.toString(),
      namespace: namespace,
      tls: tls,
    );
  }

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) {
    return redisWorkflowStoreFactory(
      uri.toString(),
      namespace: namespace,
    );
  }

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) {
    return redisScheduleStoreFactory(
      uri.toString(),
      namespace: namespace,
      lockTtl: scheduleLockTtl,
      calculator: scheduleCalculator,
      tls: tls,
    );
  }

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) {
    return redisLockStoreFactory(
      uri.toString(),
      namespace: namespace,
      tls: tls,
    );
  }

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) {
    return redisRevokeStoreFactory(
      uri.toString(),
      namespace: namespace,
      tls: tls,
    );
  }
}
