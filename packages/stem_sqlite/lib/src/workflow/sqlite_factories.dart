import 'dart:io';

import 'package:stem/stem.dart';

import '../broker/sqlite_broker.dart';
import '../backend/sqlite_result_backend.dart';
import 'sqlite_workflow_store.dart';

StemBrokerFactory sqliteBrokerFactory(
  File file, {
  Duration defaultVisibilityTimeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 250),
  Duration sweeperInterval = const Duration(seconds: 10),
  Duration deadLetterRetention = const Duration(days: 7),
}) {
  return StemBrokerFactory(
    create: () async => SqliteBroker.open(
      file,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    ),
    dispose: (broker) async {
      if (broker is SqliteBroker) {
        await broker.close();
      }
    },
  );
}

StemBackendFactory sqliteResultBackendFactory(
  File file, {
  Duration defaultTtl = const Duration(days: 1),
  Duration groupDefaultTtl = const Duration(days: 1),
  Duration heartbeatTtl = const Duration(minutes: 1),
}) {
  return StemBackendFactory(
    create: () async => SqliteResultBackend.open(
      file,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
      heartbeatTtl: heartbeatTtl,
    ),
    dispose: (backend) async {
      if (backend is SqliteResultBackend) {
        await backend.close();
      }
    },
  );
}

WorkflowStoreFactory sqliteWorkflowStoreFactory(File file) {
  return WorkflowStoreFactory(
    create: () async => SqliteWorkflowStore.open(file),
    dispose: (store) async {
      if (store is SqliteWorkflowStore) {
        await store.close();
      }
    },
  );
}
