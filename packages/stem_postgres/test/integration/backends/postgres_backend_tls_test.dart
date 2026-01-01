import 'dart:convert';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

import '../../support/postgres_test_harness.dart';

Future<void> main() async {
  final connectionString =
      Platform.environment['STEM_TEST_POSTGRES_TLS_URL'] ??
      Platform.environment['STEM_TEST_POSTGRES_URL'];
  final caOverride = Platform.environment['STEM_TEST_POSTGRES_TLS_CA_CERT']
      ?.trim();
  final defaultCa = File('docker/testing/certs/postgres-root.crt');
  final caPath = caOverride?.isNotEmpty ?? false
      ? caOverride
      : (defaultCa.existsSync() ? defaultCa.path : null);

  if (connectionString == null ||
      connectionString.isEmpty ||
      caPath == null ||
      caPath.isEmpty) {
    test(
      'Postgres TLS backend integration requires '
      'STEM_TEST_POSTGRES_TLS_URL and CA path',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_TLS_URL (or STEM_TEST_POSTGRES_URL) and '
          'STEM_TEST_POSTGRES_TLS_CA_CERT to run Postgres TLS integration '
          'tests.',
    );
    return;
  }

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres tls result backend', (dataSource) {
    // TLS config no longer used directly by backend connection
    late PostgresResultBackend backend;

    setUp(() {
      backend = PostgresResultBackend.fromDataSource(
        dataSource,
        defaultTtl: const Duration(seconds: 5),
        groupDefaultTtl: const Duration(seconds: 5),
        heartbeatTtl: const Duration(seconds: 5),
      );
    });

    tearDown(() async {
      await backend.close();
    });

    test('signed metadata round-trips over TLS', () async {
      final signingEnv = {
        'STEM_SIGNING_KEYS':
            'primary:${base64.encode(utf8.encode('tls-secret'))}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      };
      final signingConfig = SigningConfig.fromEnvironment(signingEnv);
      final signer = PayloadSigner(signingConfig);
      final envelope = Envelope(
        name: 'reports.generate',
        args: const {'region': 'emea'},
        headers: const {},
        queue: 'tls',
        priority: 5,
        maxRetries: 2,
        visibilityTimeout: const Duration(seconds: 30),
        meta: const {'source': 'tls-integ'},
      );
      final signed = await signer.sign(envelope);

      final meta = <String, Object?>{
        signatureHeader: signed.headers[signatureHeader],
        signatureKeyHeader: signed.headers[signatureKeyHeader],
        'source': 'tls-integ',
      };

      final updates = backend.watch(signed.id);
      final updateFuture = updates.first.timeout(const Duration(seconds: 5));

      await backend.set(
        signed.id,
        TaskState.succeeded,
        payload: const {'result': 'ok'},
        meta: meta,
        attempt: 1,
      );

      final fetched = await backend.get(signed.id);
      expect(fetched, isNotNull);
      expect(fetched!.meta[signatureHeader], meta[signatureHeader]);
      expect(fetched.meta[signatureKeyHeader], meta[signatureKeyHeader]);
      expect(fetched.meta['source'], 'tls-integ');

      final streamed = await updateFuture;
      expect(streamed.id, signed.id);
      expect(streamed.state, TaskState.succeeded);

      final insecureBackend = PostgresResultBackend.fromDataSource(
        dataSource,
        defaultTtl: const Duration(seconds: 5),
        groupDefaultTtl: const Duration(seconds: 5),
        heartbeatTtl: const Duration(seconds: 5),
      );

      try {
        await insecureBackend.set(
          'insecure-id',
          TaskState.queued,
        );
        final status = await insecureBackend.get('insecure-id');
        expect(status, isNotNull);
        expect(status!.state, TaskState.queued);
      } finally {
        await insecureBackend.close();
      }
    });
  }, config: harness.config);
}
