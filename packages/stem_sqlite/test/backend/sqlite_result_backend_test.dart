import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'stem_sqlite_result_backend_test',
    );
    dbFile = File('${tempDir.path}/backend.db');
  });

  tearDown(() async {
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  runResultBackendContractTests(
    adapterName: 'SQLite',
    factory: ResultBackendContractFactory(
      create: () async => SqliteResultBackend.open(
        dbFile,
        defaultTtl: const Duration(seconds: 1),
        groupDefaultTtl: const Duration(seconds: 1),
        heartbeatTtl: const Duration(seconds: 1),
        cleanupInterval: const Duration(milliseconds: 200),
      ),
      dispose: (backend) => (backend as SqliteResultBackend).close(),
      beforeStatusExpiryCheck: (backend) =>
          (backend as SqliteResultBackend).runCleanup(),
      beforeGroupExpiryCheck: (backend) =>
          (backend as SqliteResultBackend).runCleanup(),
      beforeHeartbeatExpiryCheck: (backend) =>
          (backend as SqliteResultBackend).runCleanup(),
    ),
    settings: const ResultBackendContractSettings(
      settleDelay: Duration(milliseconds: 120),
    ),
  );

  test('namespace isolates task results', () async {
    final namespaceA =
        'sqlite-backend-a-${DateTime.now().microsecondsSinceEpoch}';
    final namespaceB =
        'sqlite-backend-b-${DateTime.now().microsecondsSinceEpoch}';
    final backendA = await SqliteResultBackend.open(
      dbFile,
      namespace: namespaceA,
      defaultTtl: const Duration(seconds: 2),
      groupDefaultTtl: const Duration(seconds: 2),
      heartbeatTtl: const Duration(seconds: 2),
      cleanupInterval: const Duration(milliseconds: 200),
    );
    final backendB = await SqliteResultBackend.open(
      dbFile,
      namespace: namespaceB,
      defaultTtl: const Duration(seconds: 2),
      groupDefaultTtl: const Duration(seconds: 2),
      heartbeatTtl: const Duration(seconds: 2),
      cleanupInterval: const Duration(milliseconds: 200),
    );
    try {
      const taskId = 'namespace-task';
      await backendA.set(
        taskId,
        TaskState.succeeded,
        payload: const {'value': 'ok'},
      );

      final fromA = await backendA.get(taskId);
      final fromB = await backendB.get(taskId);

      expect(fromA, isNotNull);
      expect(fromB, isNull);
    } finally {
      await backendA.close();
      await backendB.close();
    }
  });
}
