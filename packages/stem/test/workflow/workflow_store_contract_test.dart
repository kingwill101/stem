import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

void main() {
  final sqliteDirectories = Expando<Directory>('sqlite-directory');

  runWorkflowStoreContractTests(
    adapterName: 'in-memory',
    factory: WorkflowStoreContractFactory(
      create: () async => InMemoryWorkflowStore(),
    ),
  );

  runWorkflowStoreContractTests(
    adapterName: 'sqlite',
    factory: WorkflowStoreContractFactory(
      create: () async {
        final tmpDir = await Directory.systemTemp.createTemp('wf-sqlite');
        final file = File(p.join(tmpDir.path, 'workflow.sqlite'));
        final store = SqliteWorkflowStore.open(file);
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
    ),
  );

  final redisUrl =
      Platform.environment['REDIS_URL'] ?? 'redis://127.0.0.1:56379/0';
  runWorkflowStoreContractTests(
    adapterName: 'redis',
    factory: WorkflowStoreContractFactory(
      create: () async => RedisWorkflowStore.connect(
        redisUrl,
        namespace: 'wf_contract_${DateTime.now().microsecondsSinceEpoch}',
      ),
      dispose: (store) async {
        if (store is RedisWorkflowStore) {
          await store.close();
        }
      },
    ),
  );

  final postgresUrl =
      Platform.environment['POSTGRES_URL'] ??
      'postgresql://postgres:postgres@127.0.0.1:65432/stem_test';
  runWorkflowStoreContractTests(
    adapterName: 'postgres',
    factory: WorkflowStoreContractFactory(
      create: () async => PostgresWorkflowStore.connect(
        postgresUrl,
        namespace: 'wf_contract_${DateTime.now().microsecondsSinceEpoch}',
      ),
      dispose: (store) async {
        if (store is PostgresWorkflowStore) {
          await store.close();
        }
      },
    ),
  );
}
