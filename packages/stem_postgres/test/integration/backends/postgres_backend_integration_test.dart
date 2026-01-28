import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

import '../../support/postgres_test_harness.dart';

Future<void> main() async {
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

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres result backend', (dataSource) {
    runResultBackendContractTests(
      adapterName: 'Postgres',
      factory: ResultBackendContractFactory(
        create: () async {
          return PostgresResultBackend.fromDataSource(
            dataSource,
            namespace: 'contract',
            defaultTtl: const Duration(seconds: 1),
            groupDefaultTtl: const Duration(seconds: 1),
            heartbeatTtl: const Duration(seconds: 1),
            runMigrations: false,
          );
        },
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
      final backendA = await PostgresResultBackend.fromDataSource(
        dataSource,
        namespace: namespaceA,
        defaultTtl: const Duration(seconds: 2),
        groupDefaultTtl: const Duration(seconds: 2),
        heartbeatTtl: const Duration(seconds: 2),
        runMigrations: false,
      );
      final backendB = await PostgresResultBackend.fromDataSource(
        dataSource,
        namespace: namespaceB,
        defaultTtl: const Duration(seconds: 2),
        groupDefaultTtl: const Duration(seconds: 2),
        heartbeatTtl: const Duration(seconds: 2),
        runMigrations: false,
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

    test('listTaskStatuses returns filtered task records', () async {
      final namespace = 'backend-list-${DateTime.now().microsecondsSinceEpoch}';
      final backend = await PostgresResultBackend.fromDataSource(
        dataSource,
        namespace: namespace,
        defaultTtl: const Duration(seconds: 2),
        groupDefaultTtl: const Duration(seconds: 2),
        heartbeatTtl: const Duration(seconds: 2),
        runMigrations: false,
      );
      try {
        await backend.set(
          'task-1',
          TaskState.queued,
          meta: const {'queue': 'default', 'kind': 'demo'},
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await backend.set(
          'task-2',
          TaskState.succeeded,
          meta: const {'queue': 'default', 'kind': 'demo'},
        );
        await backend.set(
          'task-3',
          TaskState.running,
          meta: const {'queue': 'other', 'kind': 'demo'},
        );

        final page = await backend.listTaskStatuses(
          const TaskStatusListRequest(
            queue: 'default',
            meta: {'kind': 'demo'},
            limit: 10,
          ),
        );

        expect(page.items, hasLength(2));
        expect(page.items.first.status.id, 'task-2');
        expect(page.items.first.updatedAt, isA<DateTime>());
      } finally {
        await backend.close();
      }
    });

    test('fromDataSource initializes lazy data sources', () async {
      final schema = dataSource.options.defaultSchema;
      if (schema == null || schema.isEmpty) {
        return;
      }

      final schemaUrl = _withSearchPath(connectionString, schema);
      final lazyDataSource = createDataSource(connectionString: schemaUrl);
      final backend = await PostgresResultBackend.fromDataSource(
        lazyDataSource,
        namespace: 'lazy-init',
        defaultTtl: const Duration(seconds: 1),
        groupDefaultTtl: const Duration(seconds: 1),
        heartbeatTtl: const Duration(seconds: 1),
        runMigrations: true,
      );

      try {
        await backend.set(
          'lazy-init-task',
          TaskState.succeeded,
          payload: const {'ok': true},
        );
        final status = await backend.get('lazy-init-task');
        expect(status, isNotNull);
      } finally {
        await backend.close();
        await lazyDataSource.dispose();
      }
    });
  }, config: harness.config);
}

String _withSearchPath(String url, String schema) {
  final uri = Uri.parse(url);
  final optionsValue = '-c search_path=$schema,public';
  final params = Map<String, String>.from(uri.queryParameters);
  params['options'] = optionsValue;
  return uri.replace(queryParameters: params).toString();
}
