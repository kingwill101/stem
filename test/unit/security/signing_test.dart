import 'dart:convert';

import 'package:contextual/contextual.dart';
import 'package:cryptography/cryptography.dart';
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
      expect(config.hmacSecrets.containsKey('old'), isTrue);
      expect(config.algorithm, equals(SigningAlgorithm.hmacSha256));
    });

    test('disabled when keys missing', () {
      final config = SigningConfig.fromEnvironment({});
      expect(config.isEnabled, isFalse);
    });
  });

  group('PayloadSigner (HMAC)', () {
    final secret = base64.encode(utf8.encode('another-secret'));
    final config = SigningConfig.fromEnvironment({
      'STEM_SIGNING_KEYS': 'primary:$secret',
      'STEM_SIGNING_ACTIVE_KEY': 'primary',
    });
    final signer = PayloadSigner(config);

    test('sign attaches headers and verify succeeds', () async {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = await signer.sign(envelope);

      expect(signed.headers.containsKey(signatureHeader), isTrue);
      expect(signed.headers.containsKey(signatureKeyHeader), isTrue);
      await signer.verify(signed);
    });

    test('verify fails when payload is tampered', () async {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = await signer.sign(envelope);
      final tampered = signed.copyWith(args: const {'value': 2});

      await expectLater(
        signer.verify(tampered),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('verify fails for unknown key', () async {
      final envelope = Envelope(name: 'demo.task', args: const {});
      final signed = await signer.sign(envelope);
      final headers = Map<String, String>.from(signed.headers)
        ..[signatureKeyHeader] = 'missing';
      final mutated = signed.copyWith(headers: headers);

      await expectLater(
        signer.verify(mutated),
        throwsA(isA<SignatureVerificationException>()),
      );
    });
  });

  group('PayloadSigner (Ed25519)', () {
    late SigningConfig config;
    late PayloadSigner signer;

    setUpAll(() async {
      final keyPair = await Ed25519().newKeyPair();
      final privateKey = await keyPair.extractPrivateKeyBytes();
      final publicKey = (await keyPair.extractPublicKey()).bytes;

      config = SigningConfig.fromEnvironment({
        'STEM_SIGNING_ALGORITHM': 'ed25519',
        'STEM_SIGNING_PUBLIC_KEYS': 'primary:${base64.encode(publicKey)}',
        'STEM_SIGNING_PRIVATE_KEYS': 'primary:${base64.encode(privateKey)}',
        'STEM_SIGNING_ACTIVE_KEY': 'primary',
      });
      signer = PayloadSigner(config);
    });

    test('sign and verify succeeds', () async {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 42});
      final signed = await signer.sign(envelope);
      await signer.verify(signed);
    });

    test('verify fails with tampered payload', () async {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = await signer.sign(envelope);
      final tampered = signed.copyWith(args: const {'value': 2});

      await expectLater(
        signer.verify(tampered),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('verify fails for unknown public key', () async {
      final envelope = Envelope(name: 'demo.task', args: const {'value': 1});
      final signed = await signer.sign(envelope);
      final headers = Map<String, String>.from(signed.headers)
        ..[signatureKeyHeader] = 'unknown';
      final mutated = signed.copyWith(headers: headers);

      await expectLater(
        signer.verify(mutated),
        throwsA(isA<SignatureVerificationException>()),
      );
    });
  });

  group('PayloadSigner guardrails', () {
    late _RecordingLogDriver driver;

    setUp(() {
      driver = _RecordingLogDriver();
      stemLogger.addChannel('test-signing-guardrails', driver);
    });

    tearDown(() {
      stemLogger.removeChannel('test-signing-guardrails');
    });

    test(
      'logs warning when private key missing for active Ed25519 key',
      () async {
        final keyPair = await Ed25519().newKeyPair();
        final publicKey = (await keyPair.extractPublicKey()).bytes;

        final config = SigningConfig.fromEnvironment({
          'STEM_SIGNING_ALGORITHM': 'ed25519',
          'STEM_SIGNING_PUBLIC_KEYS': 'primary:${base64.encode(publicKey)}',
          'STEM_SIGNING_ACTIVE_KEY': 'primary',
        });
        final signer = PayloadSigner(config);

        await expectLater(
          () => signer.sign(Envelope(name: 'guardrail.test', args: const {})),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('STEM_SIGNING_PRIVATE_KEYS'),
            ),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        final warnings = driver.entries.where(
          (entry) => entry.record.level == Level.warning,
        );

        expect(
          warnings.any(
            (entry) => entry.record.message.contains(
              'Signing configuration incomplete',
            ),
          ),
          isTrue,
        );
      },
    );
  });
}

class _RecordingLogDriver extends LogDriver {
  _RecordingLogDriver() : entries = <LogEntry>[], super('recording');

  final List<LogEntry> entries;

  @override
  Future<void> log(LogEntry entry) async {
    entries.add(entry);
  }
}
