import 'dart:io';
import 'dart:math' as math;

import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_redis/stem_redis.dart';

void main() {
  final random = math.Random();

  final redisUrl =
      Platform.environment['REDIS_URL'] ?? 'redis://127.0.0.1:56379/0';
  final redisFactory = WorkflowStoreContractFactory(
    create: (clock) async => RedisWorkflowStore.connect(
      redisUrl,
      namespace:
          'wf_contract_'
          '${DateTime.now().microsecondsSinceEpoch}_'
          '${random.nextInt(999999)}',
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
}
