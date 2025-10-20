import 'dart:io';

/// TLS configuration for brokers and backends.
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
