import 'dart:collection';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import '../core/envelope.dart';

/// Header storing the base64 encoded payload signature.
const String signatureHeader = 'stem-signature';

/// Header storing the signing key identifier used to calculate the signature.
const String signatureKeyHeader = 'stem-signature-key';

/// Supported signing algorithms.
enum SigningAlgorithm {
  hmacSha256('hmac-sha256');

  const SigningAlgorithm(this.label);

  final String label;

  static SigningAlgorithm parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return SigningAlgorithm.hmacSha256;
    }
    final match = SigningAlgorithm.values.firstWhere(
      (alg) => alg.label == raw.toLowerCase(),
      orElse: () {
        throw FormatException('Unsupported signing algorithm "$raw"');
      },
    );
    return match;
  }
}

/// Configuration describing signing keys and behaviour.
class SigningConfig {
  const SigningConfig._({
    required this.activeKeyId,
    required this.keys,
    required this.algorithm,
  });

  /// Disabled configuration (no signing).
  const SigningConfig.disabled()
    : activeKeyId = null,
      keys = const {},
      algorithm = SigningAlgorithm.hmacSha256;

  /// The active signing key used for new envelopes.
  final String? activeKeyId;

  /// Map of key identifier to secret bytes that workers accept.
  final Map<String, List<int>> keys;

  /// Algorithm used to generate signatures.
  final SigningAlgorithm algorithm;

  /// Whether signing/verification should be performed.
  bool get isEnabled => activeKeyId != null && keys.isNotEmpty;

  /// Returns the secret for [keyId] if known.
  List<int>? secretFor(String keyId) => keys[keyId];

  /// Parses config from environment variables.
  factory SigningConfig.fromEnvironment(Map<String, String> env) {
    final rawKeys = env[_SigningEnv.keys]?.trim();
    if (rawKeys == null || rawKeys.isEmpty) {
      return const SigningConfig.disabled();
    }

    final parsedKeys = <String, List<int>>{};
    for (final entry in rawKeys.split(',')) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length != 2) {
        throw FormatException(
          'Invalid signing key entry "$trimmed". Expected format keyId:base64Secret',
        );
      }
      final keyId = parts[0].trim();
      if (keyId.isEmpty) {
        throw FormatException('Signing key id cannot be empty.');
      }
      try {
        parsedKeys[keyId] = base64.decode(parts[1].trim());
      } on FormatException {
        throw FormatException('Signing key "$keyId" must be base64 encoded.');
      }
    }

    if (parsedKeys.isEmpty) {
      return const SigningConfig.disabled();
    }

    final algorithm = SigningAlgorithm.parse(
      env[_SigningEnv.algorithm]?.trim(),
    );

    final activeKeyId = env[_SigningEnv.activeKey]?.trim();
    if (activeKeyId == null || activeKeyId.isEmpty) {
      throw StateError(
        'Missing ${_SigningEnv.activeKey}; required when signing keys are provided.',
      );
    }
    if (!parsedKeys.containsKey(activeKeyId)) {
      throw StateError(
        'Active signing key "$activeKeyId" not present in ${_SigningEnv.keys}.',
      );
    }

    return SigningConfig._(
      activeKeyId: activeKeyId,
      keys: Map.unmodifiable(parsedKeys),
      algorithm: algorithm,
    );
  }
}

/// Handles signing and verification of envelope payloads.
class PayloadSigner {
  PayloadSigner(this.config) {
    if (!config.isEnabled) {
      throw ArgumentError('Signing config must be enabled to create signer.');
    }
  }

  final SigningConfig config;

  static PayloadSigner? maybe(SigningConfig config) =>
      config.isEnabled ? PayloadSigner(config) : null;

  /// Returns a copy of [envelope] with signature headers attached.
  Envelope sign(Envelope envelope) {
    final keyId = config.activeKeyId!;
    final secret = config.secretFor(keyId);
    if (secret == null) {
      throw StateError('Active signing key "$keyId" is not configured.');
    }
    final canonical = _canonicalize(envelope, excludeSignatureHeaders: true);
    final digest = _digest(secret, canonical);
    final headers = Map<String, String>.from(envelope.headers)
      ..[signatureHeader] = base64.encode(digest.bytes)
      ..[signatureKeyHeader] = keyId;
    return envelope.copyWith(headers: headers);
  }

  /// Validates the envelope signature.
  void verify(Envelope envelope) {
    if (!config.isEnabled) return;
    final headers = envelope.headers;
    final signatureB64 = headers[signatureHeader];
    final keyId = headers[signatureKeyHeader];
    if (signatureB64 == null || keyId == null) {
      throw SignatureVerificationException(
        'missing signature headers',
        keyId: keyId,
      );
    }
    final secret = config.secretFor(keyId);
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
    final expected = _digest(secret, canonical);

    final eq = const ListEquality<int>();
    if (!eq.equals(actual, expected.bytes)) {
      throw SignatureVerificationException('signature mismatch', keyId: keyId);
    }
  }

  Digest _digest(List<int> secret, String canonical) {
    switch (config.algorithm) {
      case SigningAlgorithm.hmacSha256:
        return Hmac(sha256, secret).convert(utf8.encode(canonical));
    }
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
  static const activeKey = 'STEM_SIGNING_ACTIVE_KEY';
  static const algorithm = 'STEM_SIGNING_ALGORITHM';
}
