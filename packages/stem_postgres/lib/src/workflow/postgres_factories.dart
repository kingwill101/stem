import 'package:stem/stem.dart';
import 'package:stem_postgres/src/backend/postgres_backend.dart';
import 'package:stem_postgres/src/brokers/postgres_broker.dart';
import 'package:stem_postgres/src/workflow/postgres_workflow_store.dart';

/// Creates a [StemBrokerFactory] backed by PostgreSQL.
StemBrokerFactory postgresBrokerFactory(
  String uri, {
  String? applicationName,
  TlsConfig? tls,
}) {
  return StemBrokerFactory(
    create: () async =>
        PostgresBroker.connect(uri, applicationName: applicationName, tls: tls),
    dispose: (broker) async {
      if (broker is PostgresBroker) {
        await broker.close();
      }
    },
  );
}

/// Creates a [StemBackendFactory] backed by PostgreSQL.
StemBackendFactory postgresResultBackendFactory({
  Duration defaultTtl = const Duration(days: 1),
  Duration groupDefaultTtl = const Duration(days: 1),
  Duration heartbeatTtl = const Duration(minutes: 1),
}) {
  return StemBackendFactory(
    create: () async => PostgresResultBackend.connect(
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    ),
    dispose: (backend) async {
      if (backend is PostgresResultBackend) {
        await backend.close();
      }
    },
  );
}

/// Creates a [WorkflowStoreFactory] backed by PostgreSQL.
WorkflowStoreFactory postgresWorkflowStoreFactory(
  String uri, {
  String schema = 'public',
  String namespace = 'stem',
  String? applicationName,
  TlsConfig? tls,
}) {
  return WorkflowStoreFactory(
    create: () async => PostgresWorkflowStore.connect(
      uri,
      schema: schema,
      namespace: namespace,
      applicationName: applicationName,
      tls: tls,
    ),
    dispose: (store) async {
      if (store is PostgresWorkflowStore) {
        await store.close();
      }
    },
  );
}
