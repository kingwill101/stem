import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('SigningConfig', () {
    test('parses environment with base64 secrets', () {
      final secret = base64.encode(utf8.encode('super-secret'));
      final oldSecret = base64.encode(utf8.encode('old-secret'));

      final config = SigningConfig.fromEnvironment({
        'STEM_SIGNING_KEYS': 'current:$secret,old:$oldSecret',
        'STEM_SIGNING_ACTIVE_KEY': 'current',
        'STEM_SIGNING_ALGORITHM': 'hmac-sha256',
      });

      expect(config.isEnabled, isTrue);
      expect(config.activeKeyId, equals('current'));
      expect(config.keys.containsKey('old'), isTrue);
      expect(config.algorithm, equals(SigningAlgorithm.hmacSha256));
    });

    test('disabled when keys missing', () {
      final config = SigningConfig.fromEnvironment({});
      expect(config.isEnabled, isFalse);
    });
  });

  group('PayloadSigner', () {
    final secret = base64.encode(utf8.encode('another-secret'));
    final config = SigningConfig.fromEnvironment({
      'STEM_SIGNING_KEYS': 'primary:$secret',
      'STEM_SIGNING_ACTIVE_KEY': 'primary',
    });
    final signer = PayloadSigner(config);

    test('sign attaches headers and verify succeeds', () {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = signer.sign(envelope);

      expect(signed.headers.containsKey(signatureHeader), isTrue);
      expect(signed.headers.containsKey(signatureKeyHeader), isTrue);
      expect(() => signer.verify(signed), returnsNormally);
    });

    test('verify fails when payload is tampered', () {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = signer.sign(envelope);
      final tampered = signed.copyWith(args: const {'value': 2});

      expect(
        () => signer.verify(tampered),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('verify fails for unknown key', () {
      final envelope = Envelope(name: 'demo.task', args: const {});
      final signed = signer.sign(envelope);
      final headers = Map<String, String>.from(signed.headers)
        ..[signatureKeyHeader] = 'missing';
      final mutated = signed.copyWith(headers: headers);

      expect(
        () => signer.verify(mutated),
        throwsA(isA<SignatureVerificationException>()),
      );
    });
  });
}
