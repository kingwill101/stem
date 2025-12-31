import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

void main() {
  final sqliteDirectories = Expando<Directory>('sqlite-directory');

  final inMemoryFactory = WorkflowStoreContractFactory(
    create: (clock) async => InMemoryWorkflowStore(clock: clock),
  );
  runWorkflowStoreContractTests(
    adapterName: 'in-memory',
    factory: inMemoryFactory,
  );
  runWorkflowScriptFacadeTests(
    adapterName: 'in-memory',
    factory: inMemoryFactory,
  );

  final sqliteFactory = WorkflowStoreContractFactory(
    create: (clock) async {
      final tmpDir = await Directory.systemTemp.createTemp('wf-sqlite');
      final file = File(p.join(tmpDir.path, 'workflow.sqlite'));
      final store = await SqliteWorkflowStore.open(file, clock: clock);
      sqliteDirectories[store] = tmpDir;
      return store;
    },
    dispose: (store) async {
      if (store is SqliteWorkflowStore) {
        await store.close();
        final directory = sqliteDirectories[store];
        if (directory != null && directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      }
    },
  );
  runWorkflowStoreContractTests(adapterName: 'sqlite', factory: sqliteFactory);
  runWorkflowScriptFacadeTests(adapterName: 'sqlite', factory: sqliteFactory);

  final redisUrl =
      Platform.environment['REDIS_URL'] ?? 'redis://127.0.0.1:56379/0';
  final redisFactory = WorkflowStoreContractFactory(
    create: (clock) async => RedisWorkflowStore.connect(
      redisUrl,
      namespace: 'wf_contract_${DateTime.now().microsecondsSinceEpoch}',
      clock: clock,
    ),
    dispose: (store) async {
      if (store is RedisWorkflowStore) {
        await store.close();
      }
    },
  );
  runWorkflowStoreContractTests(adapterName: 'redis', factory: redisFactory);
  runWorkflowScriptFacadeTests(adapterName: 'redis', factory: redisFactory);

  final postgresUrl =
      Platform.environment['POSTGRES_URL'] ??
      'postgresql://postgres:postgres@127.0.0.1:65432/stem_test';
  final postgresFactory = WorkflowStoreContractFactory(
    create: (clock) async => PostgresWorkflowStore.connect(
      postgresUrl,
      namespace: 'wf_contract_${DateTime.now().microsecondsSinceEpoch}',
      clock: clock,
    ),
    dispose: (store) async {
      if (store is PostgresWorkflowStore) {
        await store.close();
      }
    },
  );
  runWorkflowStoreContractTests(
    adapterName: 'postgres',
    factory: postgresFactory,
  );
  runWorkflowScriptFacadeTests(
    adapterName: 'postgres',
    factory: postgresFactory,
  );
}
