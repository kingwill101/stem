import 'dart:io';

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
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  runResultBackendContractTests(
    adapterName: 'SQLite',
    factory: ResultBackendContractFactory(
      create: () async => SqliteResultBackend.open(
        dbFile,
        defaultTtl: const Duration(milliseconds: 200),
        groupDefaultTtl: const Duration(milliseconds: 200),
        heartbeatTtl: const Duration(milliseconds: 200),
        cleanupInterval: const Duration(milliseconds: 200),
      ),
      dispose: (backend) => (backend as SqliteResultBackend).close(),
      beforeStatusExpiryCheck: (backend) =>
          (backend as SqliteResultBackend).runCleanup(),
    ),
    settings: const ResultBackendContractSettings(
      statusTtl: Duration(milliseconds: 200),
      groupTtl: Duration(milliseconds: 200),
      heartbeatTtl: Duration(milliseconds: 200),
      settleDelay: Duration(milliseconds: 120),
    ),
  );
}
