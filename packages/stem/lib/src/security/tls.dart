import 'dart:io';

import 'package:contextual/contextual.dart';

import 'package:stem/src/observability/logging.dart';

/// TLS configuration for brokers, result backends, and schedule stores.
///
/// Populate via [TlsConfig.fromEnvironment] to consume the standard
/// environment variables:
///
/// - `STEM_TLS_CA_CERT` – path to the trusted CA bundle (optional)
/// - `STEM_TLS_CLIENT_CERT` / `STEM_TLS_CLIENT_KEY` – mutual TLS credentials
/// - `STEM_TLS_ALLOW_INSECURE` – if `true`, bypasses certificate validation
///
/// When handshakes fail the caller is expected to surface diagnostics via
/// [logTlsHandshakeFailure], which logs the endpoint, TLS metadata, and hints
/// about temporarily enabling insecure mode for debugging.
class TlsConfig {
  /// Creates a TLS configuration.
  const TlsConfig({
    this.caCertificateFile,
    this.clientCertificateFile,
    this.clientKeyFile,
    this.allowInsecure = false,
  });

  /// Builds a [TlsConfig] from environment variables.
  factory TlsConfig.fromEnvironment(Map<String, String> env) {
    String? optional(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final ca = optional(env[TlsEnvKeys.caCert]);
    final cert = optional(env[TlsEnvKeys.clientCert]);
    final key = optional(env[TlsEnvKeys.clientKey]);
    final allowInsecure =
        (env[TlsEnvKeys.allowInsecure] ?? 'false').toLowerCase().contains(
          'true',
        ) ||
        (env[TlsEnvKeys.allowInsecure] ?? '').toLowerCase() == '1';

    if (ca == null && cert == null && key == null && !allowInsecure) {
      return const TlsConfig.disabled();
    }

    return TlsConfig(
      caCertificateFile: ca,
      clientCertificateFile: cert,
      clientKeyFile: key,
      allowInsecure: allowInsecure,
    );
  }

  /// Disabled TLS configuration (no certificates, no insecure mode).
  const TlsConfig.disabled()
    : caCertificateFile = null,
      clientCertificateFile = null,
      clientKeyFile = null,
      allowInsecure = false;

  /// Path to the trusted CA bundle, if any.
  final String? caCertificateFile;

  /// Path to the client certificate chain, if any.
  final String? clientCertificateFile;

  /// Path to the client private key, if any.
  final String? clientKeyFile;

  /// Whether to allow insecure connections (skip verification).
  final bool allowInsecure;

  /// Whether any TLS configuration is enabled.
  bool get isEnabled =>
      caCertificateFile != null ||
      clientCertificateFile != null ||
      clientKeyFile != null;

  /// Builds a [SecurityContext] if certificate paths are provided.
  SecurityContext? toSecurityContext() {
    if (!isEnabled) return null;
    final context = SecurityContext();
    if (caCertificateFile != null && caCertificateFile!.isNotEmpty) {
      context.setTrustedCertificates(caCertificateFile!);
    }
    if (clientCertificateFile != null &&
        clientCertificateFile!.isNotEmpty &&
        clientKeyFile != null &&
        clientKeyFile!.isNotEmpty) {
      context
        ..useCertificateChain(clientCertificateFile!)
        ..usePrivateKey(clientKeyFile!);
    }
    return context;
  }
}

/// Environment variable keys for TLS configuration.
abstract class TlsEnvKeys {
  /// Environment variable for CA certificate path.
  static const caCert = 'STEM_TLS_CA_CERT';

  /// Environment variable for client certificate path.
  static const clientCert = 'STEM_TLS_CLIENT_CERT';

  /// Environment variable for client private key path.
  static const clientKey = 'STEM_TLS_CLIENT_KEY';

  /// Environment variable to allow insecure TLS.
  static const allowInsecure = 'STEM_TLS_ALLOW_INSECURE';
}

/// Logs diagnostic details for failed TLS handshakes.
void logTlsHandshakeFailure({
  required String component,
  required String host,
  required int port,
  required TlsConfig? config,
  required Object error,
  required StackTrace stack,
}) {
  final context = Context({
    'component': component,
    'subsystem': 'tls',
    'host': host,
    'port': port,
    'caCertificate': config?.caCertificateFile ?? 'system',
    'clientCertificate': config?.clientCertificateFile ?? 'not provided',
    'allowInsecure': config?.allowInsecure ?? false,
  });
  stemLogger
    ..warning(
      'TLS handshake failed while connecting to $component.',
      context,
    )
    ..warning(
      'If this blocks startup, verify certificate paths or temporarily set '
      'STEM_TLS_ALLOW_INSECURE=true to bypass verification during debugging.',
      context,
    )
    ..debug('TLS error: $error', context)
    ..debug(stack.toString(), context);
}
