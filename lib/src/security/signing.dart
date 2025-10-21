import 'dart:collection';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:contextual/contextual.dart';
import 'package:crypto/crypto.dart' as legacy_crypto show Hmac, sha256;
import 'package:cryptography/cryptography.dart' as crypt;

import '../core/envelope.dart';
import '../observability/logging.dart';

/// Header storing the base64 encoded payload signature.
const String signatureHeader = 'stem-signature';

/// Header storing the signing key identifier used to calculate the signature.
const String signatureKeyHeader = 'stem-signature-key';

/// Supported signing algorithms.
enum SigningAlgorithm {
  hmacSha256('hmac-sha256'),
  ed25519('ed25519');

  const SigningAlgorithm(this.label);

  final String label;

  static SigningAlgorithm parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return SigningAlgorithm.hmacSha256;
    }
    final lower = raw.toLowerCase();
    for (final algorithm in SigningAlgorithm.values) {
      if (algorithm.label == lower) {
        return algorithm;
      }
    }
    throw FormatException('Unsupported signing algorithm "$raw"');
  }
}

/// Configuration describing signing keys and behaviour.
///
/// This object is typically produced via [SigningConfig.fromEnvironment],
/// which accepts the standard `STEM_SIGNING_*` environment variables used by
/// producers and workers:
///
/// - `STEM_SIGNING_KEYS` for HMAC secrets (`keyId:base64` pairs)
/// - `STEM_SIGNING_PUBLIC_KEYS` and `STEM_SIGNING_PRIVATE_KEYS` for Ed25519
/// - `STEM_SIGNING_ACTIVE_KEY` identifying the key used for new envelopes
/// - `STEM_SIGNING_ALGORITHM` (`hmac-sha256` or `ed25519`)
///
/// Producers leverage this configuration through [PayloadSigner] and will emit
/// warnings plus fail fast when signatures cannot be generated (for example,
/// if the private key for the active Ed25519 key is missing).
class SigningConfig {
  const SigningConfig._({
    required this.activeKeyId,
    required this.algorithm,
    required this.hmacSecrets,
    required this.ed25519PublicKeys,
    required this.ed25519PrivateKeys,
  });

  /// Disabled configuration (no signing).
  const SigningConfig.disabled()
      : activeKeyId = null,
        algorithm = SigningAlgorithm.hmacSha256,
        hmacSecrets = const {},
        ed25519PublicKeys = const {},
        ed25519PrivateKeys = const {};

  /// The active signing key used for new envelopes.
  final String? activeKeyId;

  /// Algorithm used to generate signatures.
  final SigningAlgorithm algorithm;

  /// HMAC shared secrets keyed by identifier.
  final Map<String, List<int>> hmacSecrets;

  /// Ed25519 public keys keyed by identifier.
  final Map<String, List<int>> ed25519PublicKeys;

  /// Ed25519 private keys keyed by identifier.
  final Map<String, List<int>> ed25519PrivateKeys;

  /// Whether signing/verification should be performed.
  bool get isEnabled {
    switch (algorithm) {
      case SigningAlgorithm.hmacSha256:
        return activeKeyId != null && hmacSecrets.isNotEmpty;
      case SigningAlgorithm.ed25519:
        return ed25519PublicKeys.isNotEmpty;
    }
  }

  /// Whether the current configuration can sign new envelopes.
  bool get canSign {
    switch (algorithm) {
      case SigningAlgorithm.hmacSha256:
        return isEnabled;
      case SigningAlgorithm.ed25519:
        if (activeKeyId == null) return false;
        return ed25519PrivateKeys.containsKey(activeKeyId);
    }
  }

  List<int>? sharedSecretFor(String keyId) => hmacSecrets[keyId];

  List<int>? publicKeyFor(String keyId) => ed25519PublicKeys[keyId];

  List<int>? privateKeyFor(String keyId) => ed25519PrivateKeys[keyId];

  /// Parses config from environment variables.
  ///
  /// Unknown or malformed entries throw [FormatException], while missing keys
  /// fall back to [SigningConfig.disabled].
  factory SigningConfig.fromEnvironment(Map<String, String> env) {
    final algorithm = SigningAlgorithm.parse(
      env[_SigningEnv.algorithm]?.trim(),
    );
    final activeValue = env[_SigningEnv.activeKey]?.trim();
    final activeKeyId =
        (activeValue == null || activeValue.isEmpty) ? null : activeValue;

    if (algorithm == SigningAlgorithm.hmacSha256) {
      final rawKeys = env[_SigningEnv.keys]?.trim();
      if (rawKeys == null || rawKeys.isEmpty) {
        return const SigningConfig.disabled();
      }
      final parsed = _parseKeyList(rawKeys, 'signing key');
      if (parsed.isEmpty) {
        return const SigningConfig.disabled();
      }
      if (activeKeyId == null || activeKeyId.isEmpty) {
        throw StateError(
          'Missing ${_SigningEnv.activeKey}; required when signing keys are provided.',
        );
      }
      if (!parsed.containsKey(activeKeyId)) {
        throw StateError(
          'Active signing key "$activeKeyId" not present in ${_SigningEnv.keys}.',
        );
      }
      return SigningConfig._(
        activeKeyId: activeKeyId,
        algorithm: algorithm,
        hmacSecrets: Map.unmodifiable(parsed),
        ed25519PublicKeys: const {},
        ed25519PrivateKeys: const {},
      );
    }

    final publicRaw = env[_SigningEnv.publicKeys]?.trim();
    if (publicRaw == null || publicRaw.isEmpty) {
      return const SigningConfig.disabled();
    }
    final publicKeys = _parseKeyList(publicRaw, 'public key');
    final privateRaw = env[_SigningEnv.privateKeys]?.trim();
    final privateKeys = privateRaw == null || privateRaw.isEmpty
        ? <String, List<int>>{}
        : _parseKeyList(privateRaw, 'private key');

    if (activeKeyId != null && privateKeys.isNotEmpty) {
      if (!privateKeys.containsKey(activeKeyId)) {
        throw StateError(
          'Active signing key "$activeKeyId" missing from ${_SigningEnv.privateKeys}.',
        );
      }
    }

    return SigningConfig._(
      activeKeyId: activeKeyId,
      algorithm: algorithm,
      hmacSecrets: const {},
      ed25519PublicKeys: Map.unmodifiable(publicKeys),
      ed25519PrivateKeys: Map.unmodifiable(privateKeys),
    );
  }

  static Map<String, List<int>> _parseKeyList(String raw, String description) {
    final map = <String, List<int>>{};
    for (final entry in raw.split(',')) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length != 2) {
        throw FormatException(
          'Invalid $description entry "$trimmed". Expected format keyId:base64Value',
        );
      }
      final keyId = parts[0].trim();
      if (keyId.isEmpty) {
        throw FormatException('$description id cannot be empty.');
      }
      try {
        map[keyId] = base64.decode(parts[1].trim());
      } on FormatException {
        throw FormatException('$description "$keyId" must be base64 encoded.');
      }
    }
    return map;
  }
}

/// Handles signing and verification of envelope payloads.
class PayloadSigner {
  PayloadSigner(this.config);

  final SigningConfig config;
  static final _ed25519 = crypt.Ed25519();
  bool _warnedMisconfiguration = false;

  static PayloadSigner? maybe(SigningConfig config) =>
      config.isEnabled ? PayloadSigner(config) : null;

  /// Returns a copy of [envelope] with signature headers attached.
  Future<Envelope> sign(Envelope envelope) async {
    if (!config.isEnabled) {
      return envelope;
    }
    switch (config.algorithm) {
      case SigningAlgorithm.hmacSha256:
        return _signHmac(envelope);
      case SigningAlgorithm.ed25519:
        return _signEd25519(envelope);
    }
  }

  Future<Envelope> _signHmac(Envelope envelope) async {
    final keyId = config.activeKeyId!;
    final secret = config.sharedSecretFor(keyId);
    if (secret == null) {
      _warnMisconfiguration(
        'Active signing key "$keyId" is missing from STEM_SIGNING_KEYS.',
        keyId: keyId,
      );
      throw StateError(
        'Active signing key "$keyId" is not configured. '
        'Ensure STEM_SIGNING_KEYS includes "$keyId:<base64-secret>" and '
        'STEM_SIGNING_ACTIVE_KEY="$keyId".',
      );
    }
    final canonical = _canonicalize(envelope, excludeSignatureHeaders: true);
    final digest = legacy_crypto.Hmac(
      legacy_crypto.sha256,
      secret,
    ).convert(utf8.encode(canonical));
    final headers = Map<String, String>.from(envelope.headers)
      ..[signatureHeader] = base64.encode(digest.bytes)
      ..[signatureKeyHeader] = keyId;
    return envelope.copyWith(headers: headers);
  }

  Future<Envelope> _signEd25519(Envelope envelope) async {
    if (config.activeKeyId == null) {
      _warnMisconfiguration(
        'STEM_SIGNING_ACTIVE_KEY must be set when signing with Ed25519.',
      );
      throw StateError(
        '${_SigningEnv.activeKey} must be provided to sign with Ed25519. '
        'Set STEM_SIGNING_ACTIVE_KEY to the identifier of a private key.',
      );
    }
    final keyId = config.activeKeyId!;
    final privateKey = config.privateKeyFor(keyId);
    if (privateKey == null) {
      _warnMisconfiguration(
        'Private key for "$keyId" missing from STEM_SIGNING_PRIVATE_KEYS.',
        keyId: keyId,
      );
      throw StateError(
        'Missing private key for "$keyId". '
        'Provide STEM_SIGNING_PRIVATE_KEYS="$keyId:<base64-private-key>".',
      );
    }
    final publicKey = config.publicKeyFor(keyId);
    if (publicKey == null) {
      _warnMisconfiguration(
        'Public key for "$keyId" missing from STEM_SIGNING_PUBLIC_KEYS.',
        keyId: keyId,
      );
      throw StateError(
        'Missing public key for "$keyId". '
        'Provide STEM_SIGNING_PUBLIC_KEYS="$keyId:<base64-public-key>".',
      );
    }
    final canonical = _canonicalize(envelope, excludeSignatureHeaders: true);
    final keyPair = crypt.SimpleKeyPairData(
      privateKey,
      publicKey: crypt.SimplePublicKey(
        publicKey,
        type: crypt.KeyPairType.ed25519,
      ),
      type: crypt.KeyPairType.ed25519,
    );
    final signature = await _ed25519.sign(
      utf8.encode(canonical),
      keyPair: keyPair,
    );
    final headers = Map<String, String>.from(envelope.headers)
      ..[signatureHeader] = base64.encode(signature.bytes)
      ..[signatureKeyHeader] = keyId;
    return envelope.copyWith(headers: headers);
  }

  /// Validates the envelope signature.
  Future<void> verify(Envelope envelope) async {
    if (!config.isEnabled) return;
    switch (config.algorithm) {
      case SigningAlgorithm.hmacSha256:
        return _verifyHmac(envelope);
      case SigningAlgorithm.ed25519:
        return _verifyEd25519(envelope);
    }
  }

  Future<void> _verifyHmac(Envelope envelope) async {
    final headers = envelope.headers;
    final signatureB64 = headers[signatureHeader];
    final keyId = headers[signatureKeyHeader];
    if (signatureB64 == null || keyId == null) {
      throw SignatureVerificationException(
        'missing signature headers',
        keyId: keyId,
      );
    }
    final secret = config.sharedSecretFor(keyId);
    if (secret == null) {
      throw SignatureVerificationException(
        'unknown signing key "$keyId"',
        keyId: keyId,
      );
    }

    List<int> actual;
    try {
      actual = base64.decode(signatureB64);
    } on FormatException {
      throw SignatureVerificationException(
        'signature header is not base64 encoded',
        keyId: keyId,
      );
    }

    final canonical = _canonicalize(envelope, excludeSignatureHeaders: true);
    final expected = legacy_crypto.Hmac(
      legacy_crypto.sha256,
      secret,
    ).convert(utf8.encode(canonical));

    final eq = const ListEquality<int>();
    if (!eq.equals(actual, expected.bytes)) {
      throw SignatureVerificationException('signature mismatch', keyId: keyId);
    }
  }

  Future<void> _verifyEd25519(Envelope envelope) async {
    final headers = envelope.headers;
    final signatureB64 = headers[signatureHeader];
    final keyId = headers[signatureKeyHeader];
    if (signatureB64 == null || keyId == null) {
      throw SignatureVerificationException(
        'missing signature headers',
        keyId: keyId,
      );
    }
    final publicKeyBytes = config.publicKeyFor(keyId);
    if (publicKeyBytes == null) {
      throw SignatureVerificationException(
        'unknown signing key "$keyId"',
        keyId: keyId,
      );
    }
    List<int> signatureBytes;
    try {
      signatureBytes = base64.decode(signatureB64);
    } on FormatException {
      throw SignatureVerificationException(
        'signature header is not base64 encoded',
        keyId: keyId,
      );
    }

    final canonical = _canonicalize(envelope, excludeSignatureHeaders: true);
    final signature = crypt.Signature(
      signatureBytes,
      publicKey: crypt.SimplePublicKey(
        publicKeyBytes,
        type: crypt.KeyPairType.ed25519,
      ),
    );
    final ok = await _ed25519.verify(
      utf8.encode(canonical),
      signature: signature,
    );
    if (!ok) {
      throw SignatureVerificationException('signature mismatch', keyId: keyId);
    }
  }

  void _warnMisconfiguration(String message, {String? keyId}) {
    if (_warnedMisconfiguration) return;
    _warnedMisconfiguration = true;
    stemLogger.warning(
      'Signing configuration incomplete: $message',
      Context({
        'algorithm': config.algorithm.label,
        if (keyId != null) 'keyId': keyId,
      }),
    );
  }

  String _canonicalize(
    Envelope envelope, {
    bool excludeSignatureHeaders = false,
  }) {
    final map = SplayTreeMap<String, Object?>();
    map['id'] = envelope.id;
    map['name'] = envelope.name;
    map['queue'] = envelope.queue;
    map['args'] = _canonicalValue(envelope.args);
    map['meta'] = _canonicalValue(envelope.meta);
    map['headers'] = _canonicalHeaders(
      envelope.headers,
      excludeSignatureHeaders: excludeSignatureHeaders,
    );
    map['enqueuedAt'] = envelope.enqueuedAt.toUtc().toIso8601String();
    map['notBefore'] = envelope.notBefore?.toUtc().toIso8601String();
    map['priority'] = envelope.priority;
    map['attempt'] = envelope.attempt;
    map['maxRetries'] = envelope.maxRetries;
    map['visibilityTimeoutMs'] = envelope.visibilityTimeout?.inMilliseconds;
    return jsonEncode(map);
  }

  Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      value.forEach((key, v) {
        sorted[key.toString()] = _canonicalValue(v);
      });
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_canonicalValue).toList(growable: false);
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    return value;
  }

  Map<String, String> _canonicalHeaders(
    Map<String, String> headers, {
    required bool excludeSignatureHeaders,
  }) {
    final filtered = Map<String, String>.from(headers);
    if (excludeSignatureHeaders) {
      filtered.remove(signatureHeader);
      filtered.remove(signatureKeyHeader);
    }
    final sorted = SplayTreeMap<String, String>();
    filtered.forEach((key, value) {
      sorted[key] = value;
    });
    return sorted;
  }
}

/// Thrown when an envelope signature is missing or invalid.
class SignatureVerificationException implements Exception {
  SignatureVerificationException(this.message, {this.keyId});

  final String message;
  final String? keyId;

  @override
  String toString() =>
      'SignatureVerificationException(${keyId ?? 'unknown'}): $message';
}

class _SigningEnv {
  static const keys = 'STEM_SIGNING_KEYS';
  static const publicKeys = 'STEM_SIGNING_PUBLIC_KEYS';
  static const privateKeys = 'STEM_SIGNING_PRIVATE_KEYS';
  static const activeKey = 'STEM_SIGNING_ACTIVE_KEY';
  static const algorithm = 'STEM_SIGNING_ALGORITHM';
}
