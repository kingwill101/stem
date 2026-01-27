import 'package:stem/stem.dart';
import 'package:stem_postgres/src/control/postgres_revoke_store.dart';
import 'package:stem_postgres/src/scheduler/postgres_lock_store.dart';
import 'package:stem_postgres/src/scheduler/postgres_schedule_store.dart';
import 'package:stem_postgres/src/workflow/postgres_factories.dart';

/// Creates a [ScheduleStoreFactory] backed by PostgreSQL.
ScheduleStoreFactory postgresScheduleStoreFactory(
  String uri, {
  String namespace = 'stem',
  String schema = 'public',
  String? applicationName,
  TlsConfig? tls,
}) {
  return ScheduleStoreFactory(
    create: () async => PostgresScheduleStore.connect(
      uri,
      namespace: namespace,
      schema: schema,
      applicationName: applicationName,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is PostgresScheduleStore) {
        await store.close();
      }
    },
  );
}

/// Creates a [LockStoreFactory] backed by PostgreSQL.
LockStoreFactory postgresLockStoreFactory(
  String uri, {
  String namespace = 'stem',
  String schema = 'public',
  String? applicationName,
  TlsConfig? tls,
}) {
  return LockStoreFactory(
    create: () async => PostgresLockStore.connect(
      uri,
      namespace: namespace,
      schema: schema,
      applicationName: applicationName,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is PostgresLockStore) {
        await store.close();
      }
    },
  );
}

/// Creates a [RevokeStoreFactory] backed by PostgreSQL.
RevokeStoreFactory postgresRevokeStoreFactory(
  String uri, {
  String namespace = 'stem',
  String schema = 'public',
  String? applicationName,
  TlsConfig? tls,
}) {
  return RevokeStoreFactory(
    create: () async => PostgresRevokeStore.connect(
      uri,
      namespace: namespace,
      schema: schema,
      applicationName: applicationName,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is PostgresRevokeStore) {
        await store.close();
      }
    },
  );
}

/// Adapter that resolves PostgreSQL-backed factories from a `postgres://` URL.
class StemPostgresAdapter implements StemStoreAdapter {
  /// Creates a PostgreSQL adapter with optional defaults.
  const StemPostgresAdapter({
    this.namespace = 'stem',
    this.schema = 'public',
    this.applicationName,
    this.tls,
    this.backendDefaultTtl = const Duration(days: 1),
    this.backendGroupDefaultTtl = const Duration(days: 1),
    this.backendHeartbeatTtl = const Duration(minutes: 1),
  });

  /// Namespace prefix used by PostgreSQL-backed stores.
  final String namespace;

  /// Schema used for PostgreSQL tables.
  final String schema;

  /// Optional application name for PostgreSQL connections.
  final String? applicationName;

  /// Optional TLS configuration used by PostgreSQL clients.
  final TlsConfig? tls;

  /// Default TTL for task results.
  final Duration backendDefaultTtl;

  /// Default TTL for group results.
  final Duration backendGroupDefaultTtl;

  /// TTL for worker heartbeats stored in the backend.
  final Duration backendHeartbeatTtl;

  @override
  String get name => 'stem_postgres';

  @override
  bool supports(Uri uri, StemStoreKind kind) {
    return uri.scheme == 'postgres' || uri.scheme == 'postgresql';
  }

  @override
  StemBrokerFactory? brokerFactory(Uri uri) {
    return postgresBrokerFactory(
      uri.toString(),
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    );
  }

  @override
  StemBackendFactory? backendFactory(Uri uri) {
    return postgresResultBackendFactory(
      connectionString: uri.toString(),
      namespace: namespace,
      defaultTtl: backendDefaultTtl,
      groupDefaultTtl: backendGroupDefaultTtl,
      heartbeatTtl: backendHeartbeatTtl,
    );
  }

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) {
    return postgresWorkflowStoreFactory(
      uri.toString(),
      schema: schema,
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    );
  }

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) {
    return postgresScheduleStoreFactory(
      uri.toString(),
      schema: schema,
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    );
  }

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) {
    return postgresLockStoreFactory(
      uri.toString(),
      schema: schema,
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    );
  }

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) {
    return postgresRevokeStoreFactory(
      uri.toString(),
      schema: schema,
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    );
  }
}
