import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres result backend integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres result backend '
          'integration tests.',
    );
    return;
  }

  runResultBackendContractTests(
    adapterName: 'Postgres',
    factory: ResultBackendContractFactory(
      create: () async => PostgresResultBackend.connect(
        connectionString: connectionString,
        defaultTtl: const Duration(seconds: 1),
        groupDefaultTtl: const Duration(seconds: 1),
        heartbeatTtl: const Duration(seconds: 1),
      ),
      dispose: (backend) => (backend as PostgresResultBackend).close(),
    ),
    settings: const ResultBackendContractSettings(
      settleDelay: Duration(milliseconds: 250),
    ),
  );

  test('namespace isolates task results', () async {
    final namespaceA =
        'backend-ns-a-${DateTime.now().microsecondsSinceEpoch}';
    final namespaceB =
        'backend-ns-b-${DateTime.now().microsecondsSinceEpoch}';
    final backendA = await PostgresResultBackend.connect(
      connectionString: connectionString,
      namespace: namespaceA,
      defaultTtl: const Duration(seconds: 2),
      groupDefaultTtl: const Duration(seconds: 2),
      heartbeatTtl: const Duration(seconds: 2),
    );
    final backendB = await PostgresResultBackend.connect(
      connectionString: connectionString,
      namespace: namespaceB,
      defaultTtl: const Duration(seconds: 2),
      groupDefaultTtl: const Duration(seconds: 2),
      heartbeatTtl: const Duration(seconds: 2),
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
