import 'dart:io';
import 'dart:math' as math;

import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';

void main() {
  final random = math.Random();
  final postgresUrl =
      Platform.environment['POSTGRES_URL'] ??
      'postgresql://postgres:postgres@127.0.0.1:65432/stem_test';
  final postgresFactory = WorkflowStoreContractFactory(
    create: (clock) async => PostgresWorkflowStore.connect(
      postgresUrl,
      namespace:
          'wf_contract_'
          '${DateTime.now().microsecondsSinceEpoch}_'
          '${random.nextInt(999999)}',
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
