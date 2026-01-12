import 'package:stem/src/security/tls.dart';
import 'package:test/test.dart';

void main() {
  group('TlsConfig', () {
    test('fromEnvironment disables when empty', () {
      final config = TlsConfig.fromEnvironment(const {});

      expect(config.isEnabled, isFalse);
      expect(config.allowInsecure, isFalse);
      expect(config.toSecurityContext(), isNull);
    });

    test('fromEnvironment parses allowInsecure', () {
      final config = TlsConfig.fromEnvironment({
        TlsEnvKeys.allowInsecure: 'true',
      });

      expect(config.allowInsecure, isTrue);
      expect(config.isEnabled, isFalse);
    });

    test('fromEnvironment keeps certificate paths', () {
      final config = TlsConfig.fromEnvironment({
        TlsEnvKeys.caCert: '/tmp/ca.pem',
        TlsEnvKeys.clientCert: '/tmp/client.pem',
        TlsEnvKeys.clientKey: '/tmp/client.key',
      });

      expect(config.caCertificateFile, equals('/tmp/ca.pem'));
      expect(config.clientCertificateFile, equals('/tmp/client.pem'));
      expect(config.clientKeyFile, equals('/tmp/client.key'));
      expect(config.isEnabled, isTrue);
    });

    test('logTlsHandshakeFailure does not throw', () {
      final config = TlsConfig.fromEnvironment({
        TlsEnvKeys.allowInsecure: '1',
      });

      logTlsHandshakeFailure(
        component: 'broker',
        host: 'localhost',
        port: 1234,
        config: config,
        error: StateError('boom'),
        stack: StackTrace.current,
      );
    });
  });
}
