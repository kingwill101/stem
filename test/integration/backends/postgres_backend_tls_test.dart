import 'dart:convert';
import 'dart:io';

import 'package:stem/src/backend/postgres_backend.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/security/tls.dart';
import 'package:test/test.dart';

void main() {
  final connectionString =
      Platform.environment['STEM_TEST_POSTGRES_TLS_URL'] ??
      Platform.environment['STEM_TEST_POSTGRES_URL'];
  final caOverride = Platform.environment['STEM_TEST_POSTGRES_TLS_CA_CERT']
      ?.trim();
  final defaultCa = File('docker/testing/certs/postgres-root.crt');
  final caPath = caOverride?.isNotEmpty == true
      ? caOverride
      : (defaultCa.existsSync() ? defaultCa.path : null);

  if (connectionString == null ||
      connectionString.isEmpty ||
      caPath == null ||
      caPath.isEmpty) {
    test(
      'Postgres TLS backend integration requires STEM_TEST_POSTGRES_TLS_URL and CA path',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_TLS_URL (or STEM_TEST_POSTGRES_URL) and STEM_TEST_POSTGRES_TLS_CA_CERT to run Postgres TLS integration tests.',
    );
    return;
  }

  final tls = TlsConfig(caCertificateFile: caPath, allowInsecure: false);

  late PostgresResultBackend backend;

  setUp(() async {
    backend = await PostgresResultBackend.connect(
      connectionString,
      namespace: 'stem_tls',
      applicationName: 'stem-postgres-backend-tls-test',
      defaultTtl: const Duration(seconds: 5),
      groupDefaultTtl: const Duration(seconds: 5),
      heartbeatTtl: const Duration(seconds: 5),
      tls: tls,
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

    final insecureBackend = await PostgresResultBackend.connect(
      connectionString,
      namespace: 'stem_tls',
      applicationName: 'stem-postgres-backend-tls-test-insecure',
      defaultTtl: const Duration(seconds: 5),
      groupDefaultTtl: const Duration(seconds: 5),
      heartbeatTtl: const Duration(seconds: 5),
      tls: const TlsConfig(allowInsecure: true),
    );

    try {
      await insecureBackend.set(
        'insecure-id',
        TaskState.queued,
        meta: const {},
        attempt: 0,
      );
      final status = await insecureBackend.get('insecure-id');
      expect(status, isNotNull);
      expect(status!.state, TaskState.queued);
    } finally {
      await insecureBackend.close();
    }
  });
}
