import 'dart:io';

/// Configuration source for Stem clients and worker processes.
class StemConfig {
  StemConfig({
    required this.brokerUrl,
    this.resultBackendUrl,
    this.scheduleStoreUrl,
    this.defaultQueue = 'default',
    this.prefetchMultiplier = 2,
    this.defaultMaxRetries = 3,
  });

  /// Broker connection string (e.g. redis://localhost:6379).
  final String brokerUrl;

  /// Optional result backend connection string.
  final String? resultBackendUrl;

  /// Optional schedule store connection string.
  final String? scheduleStoreUrl;

  /// Default queue for tasks without explicit routing.
  final String defaultQueue;

  /// Prefetch multiplier applied to worker concurrency.
  final int prefetchMultiplier;

  /// Global fallback for tasks without explicit max retries.
  final int defaultMaxRetries;

  /// Construct configuration from environment variables.
  factory StemConfig.fromEnvironment([Map<String, String>? env]) {
    final environment = env ?? Platform.environment;
    final broker = environment[_Keys.brokerUrl];
    if (broker == null || broker.isEmpty) {
      throw StateError(
        'Missing ${_Keys.brokerUrl} environment variable (e.g. redis://host:6379).',
      );
    }
    return StemConfig(
      brokerUrl: broker,
      resultBackendUrl: _optional(environment[_Keys.resultBackendUrl]),
      scheduleStoreUrl: _optional(environment[_Keys.scheduleStoreUrl]),
      defaultQueue: environment[_Keys.defaultQueue]?.trim().isNotEmpty == true
          ? environment[_Keys.defaultQueue]!.trim()
          : 'default',
      prefetchMultiplier: _parseInt(
        environment[_Keys.prefetchMultiplier],
        fallback: 2,
        min: 1,
      ),
      defaultMaxRetries: _parseInt(
        environment[_Keys.defaultMaxRetries],
        fallback: 3,
        min: 0,
      ),
    );
  }

  static String? _optional(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int _parseInt(
    String? input, {
    required int fallback,
    required int min,
  }) {
    if (input == null || input.trim().isEmpty) return fallback;
    final parsed = int.tryParse(input.trim());
    if (parsed == null || parsed < min) return fallback;
    return parsed;
  }

  StemConfig copyWith({
    String? brokerUrl,
    String? resultBackendUrl,
    String? scheduleStoreUrl,
    String? defaultQueue,
    int? prefetchMultiplier,
    int? defaultMaxRetries,
  }) {
    return StemConfig(
      brokerUrl: brokerUrl ?? this.brokerUrl,
      resultBackendUrl: resultBackendUrl ?? this.resultBackendUrl,
      scheduleStoreUrl: scheduleStoreUrl ?? this.scheduleStoreUrl,
      defaultQueue: defaultQueue ?? this.defaultQueue,
      prefetchMultiplier: prefetchMultiplier ?? this.prefetchMultiplier,
      defaultMaxRetries: defaultMaxRetries ?? this.defaultMaxRetries,
    );
  }
}

/// Well-known environment variable keys.
abstract class _Keys {
  static const brokerUrl = 'STEM_BROKER_URL';
  static const resultBackendUrl = 'STEM_RESULT_BACKEND_URL';
  static const scheduleStoreUrl = 'STEM_SCHEDULE_STORE_URL';
  static const defaultQueue = 'STEM_DEFAULT_QUEUE';
  static const prefetchMultiplier = 'STEM_PREFETCH_MULTIPLIER';
  static const defaultMaxRetries = 'STEM_DEFAULT_MAX_RETRIES';
}
