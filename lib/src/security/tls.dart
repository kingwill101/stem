import 'dart:io';

import 'package:contextual/contextual.dart';

import '../observability/logging.dart';

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
  const TlsConfig({
    this.caCertificateFile,
    this.clientCertificateFile,
    this.clientKeyFile,
    this.allowInsecure = false,
  });

  const TlsConfig.disabled()
      : caCertificateFile = null,
        clientCertificateFile = null,
        clientKeyFile = null,
        allowInsecure = false;

  final String? caCertificateFile;
  final String? clientCertificateFile;
  final String? clientKeyFile;
  final bool allowInsecure;

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
      context.useCertificateChain(clientCertificateFile!);
      context.usePrivateKey(clientKeyFile!);
    }
    return context;
  }

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
}

abstract class TlsEnvKeys {
  static const caCert = 'STEM_TLS_CA_CERT';
  static const clientCert = 'STEM_TLS_CLIENT_CERT';
  static const clientKey = 'STEM_TLS_CLIENT_KEY';
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
    'host': host,
    'port': port,
    'caCertificate': config?.caCertificateFile ?? 'system',
    'clientCertificate': config?.clientCertificateFile ?? 'not provided',
    'allowInsecure': config?.allowInsecure ?? false,
  });
  stemLogger.warning(
    'TLS handshake failed while connecting to $component.',
    context,
  );
  stemLogger.warning(
    'If this blocks startup, verify certificate paths or temporarily set '
    'STEM_TLS_ALLOW_INSECURE=true to bypass verification during debugging.',
    context,
  );
  stemLogger.debug('TLS error: $error', context);
  stemLogger.debug(stack.toString(), context);
}
