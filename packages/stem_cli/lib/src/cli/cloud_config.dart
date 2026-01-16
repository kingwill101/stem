/// Shared helpers for configuring Stem Cloud HTTP clients from environment.
const String kStemCloudApiKeyEnv = 'STEM_CLOUD_API_KEY';
const String kStemCloudNamespaceEnv = 'STEM_CLOUD_NAMESPACE';
const String kStemNamespaceEnv = 'STEM_NAMESPACE';
const String kStemWorkerNamespaceEnv = 'STEM_WORKER_NAMESPACE';

/// Returns the configured Stem Cloud API key.
String resolveStemCloudApiKey(
  Map<String, String> environment, {
  String? override,
}) {
  final candidate = override?.trim();
  if (candidate != null && candidate.isNotEmpty) return candidate;
  final envValue = environment[kStemCloudApiKeyEnv]?.trim();
  if (envValue != null && envValue.isNotEmpty) return envValue;
  throw StateError(
    'Missing $kStemCloudApiKeyEnv for cloud schedule/revoke store.',
  );
}

/// Returns the configured namespace for cloud requests, if any.
String? resolveStemCloudNamespace(Map<String, String> environment) {
  final candidates = <String>[
    kStemCloudNamespaceEnv,
    kStemNamespaceEnv,
    kStemWorkerNamespaceEnv,
  ];
  for (final key in candidates) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
