import 'dart:io';

/// TLS configuration used when connecting to Stem backplanes.
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

    final ca = optional(env['STEM_TLS_CA_CERT']);
    final cert = optional(env['STEM_TLS_CLIENT_CERT']);
    final key = optional(env['STEM_TLS_CLIENT_KEY']);
    final allowInsecure =
        (env['STEM_TLS_ALLOW_INSECURE'] ?? 'false').toLowerCase() == 'true' ||
        (env['STEM_TLS_ALLOW_INSECURE'] ?? '').trim() == '1';

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
