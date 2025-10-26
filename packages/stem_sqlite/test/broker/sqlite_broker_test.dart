import 'dart:io';

import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('stem_sqlite_broker_test');
    dbFile = File('${tempDir.path}/broker.db');
  });

  tearDown(() async {
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  runBrokerContractTests(
    adapterName: 'SQLite',
    factory: BrokerContractFactory(
      create: () async => SqliteBroker.open(
        dbFile,
        defaultVisibilityTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 25),
        sweeperInterval: const Duration(milliseconds: 75),
      ),
      dispose: (broker) => (broker as SqliteBroker).close(),
    ),
    settings: const BrokerContractSettings(
      visibilityTimeout: Duration(milliseconds: 300),
      leaseExtension: Duration(milliseconds: 300),
      queueSettleDelay: Duration(milliseconds: 250),
      replayDelay: Duration(milliseconds: 250),
    ),
  );
}
