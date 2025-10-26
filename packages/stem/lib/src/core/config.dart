import 'dart:io';

import '../security/signing.dart';
import '../security/tls.dart';

/// Configuration source for Stem clients and worker processes.
///
/// Instances are commonly created via [StemConfig.fromEnvironment], which
/// reads the standard `STEM_*` environment variables used across the CLI,
/// producers, and workers. Besides broker and backend connectivity it embeds
/// security helpers such as [SigningConfig] and [TlsConfig], ensuring that
/// producers log actionable warnings when signing misconfigurations are
/// detected.
class StemConfig {
  StemConfig({
    required this.brokerUrl,
    this.resultBackendUrl,
    this.scheduleStoreUrl,
    this.revokeStoreUrl,
    this.defaultQueue = 'default',
    this.prefetchMultiplier = 2,
    this.defaultMaxRetries = 3,
    this.routingConfigPath,
    List<String>? workerQueues,
    List<String>? workerBroadcasts,
    SigningConfig? signing,
    TlsConfig? tls,
  }) : workerQueues = List.unmodifiable(workerQueues ?? const []),
       workerBroadcasts = List.unmodifiable(workerBroadcasts ?? const []),
       signing = signing ?? const SigningConfig.disabled(),
       tls = tls ?? const TlsConfig.disabled();

  /// Broker connection string (e.g. redis://localhost:6379).
  final String brokerUrl;

  /// Optional result backend connection string.
  final String? resultBackendUrl;

  /// Optional schedule store connection string.
  final String? scheduleStoreUrl;

  /// Optional revoke store connection string.
  final String? revokeStoreUrl;

  /// Default queue for tasks without explicit routing.
  final String defaultQueue;

  /// Prefetch multiplier applied to worker concurrency.
  final int prefetchMultiplier;

  /// Global fallback for tasks without explicit max retries.
  final int defaultMaxRetries;

  /// Optional path to a routing configuration file (YAML/JSON).
  final String? routingConfigPath;

  /// Explicit queue subscriptions for worker processes (comma separated env).
  final List<String> workerQueues;

  /// Broadcast channel subscriptions for worker processes.
  final List<String> workerBroadcasts;

  /// Payload signing configuration derived from `STEM_SIGNING_*` variables.
  ///
  /// When producers call [PayloadSigner.sign] with an incomplete configuration
  /// (for example, missing the private key for the active Ed25519 key) Stem
  /// logs a warning and fails enqueue attempts to surface the issue quickly.
  final SigningConfig signing;

  /// TLS configuration for broker/backends populated from `STEM_TLS_*`.
  ///
  /// Handshake failures include host, certificate, and allow-insecure settings
  /// to simplify troubleshooting; use `STEM_TLS_ALLOW_INSECURE=true` only for
  /// short-lived debugging sessions.
  final TlsConfig tls;

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
      revokeStoreUrl: _optional(environment[_Keys.revokeStoreUrl]),
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
      routingConfigPath: _optional(environment[_Keys.routingConfigPath]),
      workerQueues: _parseList(environment[_Keys.workerQueues]),
      workerBroadcasts: _parseList(environment[_Keys.workerBroadcasts]),
      signing: SigningConfig.fromEnvironment(environment),
      tls: TlsConfig.fromEnvironment(environment),
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

  static List<String> _parseList(String? input) {
    if (input == null || input.trim().isEmpty) return const [];
    final seen = <String>{};
    final values = <String>[];
    for (final part in input.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        values.add(trimmed);
      }
    }
    return values;
  }

  StemConfig copyWith({
    String? brokerUrl,
    String? resultBackendUrl,
    String? scheduleStoreUrl,
    String? revokeStoreUrl,
    String? defaultQueue,
    int? prefetchMultiplier,
    int? defaultMaxRetries,
    String? routingConfigPath,
    List<String>? workerQueues,
    List<String>? workerBroadcasts,
    SigningConfig? signing,
    TlsConfig? tls,
  }) {
    return StemConfig(
      brokerUrl: brokerUrl ?? this.brokerUrl,
      resultBackendUrl: resultBackendUrl ?? this.resultBackendUrl,
      scheduleStoreUrl: scheduleStoreUrl ?? this.scheduleStoreUrl,
      revokeStoreUrl: revokeStoreUrl ?? this.revokeStoreUrl,
      defaultQueue: defaultQueue ?? this.defaultQueue,
      prefetchMultiplier: prefetchMultiplier ?? this.prefetchMultiplier,
      defaultMaxRetries: defaultMaxRetries ?? this.defaultMaxRetries,
      routingConfigPath: routingConfigPath ?? this.routingConfigPath,
      workerQueues: workerQueues ?? this.workerQueues,
      workerBroadcasts: workerBroadcasts ?? this.workerBroadcasts,
      signing: signing ?? this.signing,
      tls: tls ?? this.tls,
    );
  }
}

/// Well-known environment variable keys.
abstract class _Keys {
  static const brokerUrl = 'STEM_BROKER_URL';
  static const resultBackendUrl = 'STEM_RESULT_BACKEND_URL';
  static const scheduleStoreUrl = 'STEM_SCHEDULE_STORE_URL';
  static const revokeStoreUrl = 'STEM_REVOKE_STORE_URL';
  static const defaultQueue = 'STEM_DEFAULT_QUEUE';
  static const prefetchMultiplier = 'STEM_PREFETCH_MULTIPLIER';
  static const defaultMaxRetries = 'STEM_DEFAULT_MAX_RETRIES';
  static const routingConfigPath = 'STEM_ROUTING_CONFIG';
  static const workerQueues = 'STEM_WORKER_QUEUES';
  static const workerBroadcasts = 'STEM_WORKER_BROADCASTS';
}
