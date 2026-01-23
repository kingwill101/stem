/// Shared helpers for configuring Stem Cloud HTTP clients from environment.
const String kStemCloudAccessTokenEnv = 'STEM_CLOUD_ACCESS_TOKEN';
const String kStemCloudApiKeyEnv = 'STEM_CLOUD_API_KEY';
const String kStemCloudNamespaceEnv = 'STEM_CLOUD_NAMESPACE';
const String kStemNamespaceEnv = 'STEM_NAMESPACE';
const String kStemWorkerNamespaceEnv = 'STEM_WORKER_NAMESPACE';

/// Returns the configured Stem Cloud API key.
String resolveStemCloudApiKey(
  Map<String, String> environment, {
  String? override,
}) {
  final token = resolveStemCloudAuthToken(environment, override: override);
  if (token != null) return token;
  throw StateError(
    'Missing $kStemCloudAccessTokenEnv or $kStemCloudApiKeyEnv for cloud '
    'schedule/revoke store.',
  );
}

/// Returns an optional Stem Cloud auth token from environment or override.
String? resolveStemCloudAuthToken(
  Map<String, String> environment, {
  String? override,
}) {
  final candidate = override?.trim();
  if (candidate != null && candidate.isNotEmpty) return candidate;
  final envKeys = <String>[kStemCloudAccessTokenEnv, kStemCloudApiKeyEnv];
  for (final key in envKeys) {
    final envValue = environment[key]?.trim();
    if (envValue != null && envValue.isNotEmpty) return envValue;
  }
  return null;
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
