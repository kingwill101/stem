import 'dart:io';

import 'package:stem/stem.dart';

/// Loads routing configuration into a [RoutingRegistry], providing friendlier
/// error messages than the raw YAML parsing utilities.
class RoutingConfigLoader {
  const RoutingConfigLoader(this.config);

  final StemRoutingContext config;

  /// Loads the routing registry from the configured path or returns the legacy
  /// single-queue registry when no file is specified.
  RoutingRegistry load() {
    final path = config.configPath;
    if (path == null || path.trim().isEmpty) {
      return RoutingRegistry(RoutingConfig.legacy());
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'Routing config "$path" not found. Provide a valid path via '
        'STEM_ROUTING_CONFIG or run `stem routing dump --sample`.',
      );
    }
    try {
      final contents = file.readAsStringSync();
      final routingConfig = RoutingConfig.fromYaml(contents);
      return RoutingRegistry(routingConfig);
    } on FormatException catch (error) {
      throw StateError(
        'Failed to parse routing config "$path": ${error.message}',
      );
    }
  }
}

/// Context required to resolve routing subscriptions.
class StemRoutingContext {
  const StemRoutingContext({required this.defaultQueue, this.configPath});

  factory StemRoutingContext.fromConfig(StemConfig config) =>
      StemRoutingContext(
        defaultQueue: config.defaultQueue,
        configPath: config.routingConfigPath,
      );

  final String defaultQueue;
  final String? configPath;
}

/// Helper that translates queue/broadcast selections into a
/// [RoutingSubscription], validating against the loaded routing registry.
class WorkerSubscriptionBuilder {
  WorkerSubscriptionBuilder({
    required this.registry,
    required this.defaultQueue,
  });

  final RoutingRegistry registry;
  final String defaultQueue;

  RoutingSubscription build({List<String>? queues, List<String>? broadcasts}) {
    final resolvedQueues = _resolveQueues(queues);
    final resolvedBroadcasts = _resolveBroadcasts(broadcasts);
    return RoutingSubscription(
      queues: resolvedQueues,
      broadcastChannels: resolvedBroadcasts,
    );
  }

  List<String> _resolveQueues(List<String>? requested) {
    final inputs = (requested != null && requested.isNotEmpty)
        ? requested
        : [defaultQueue];
    final seen = <String>{};
    final resolved = <String>[];
    for (final alias in inputs) {
      final trimmed = alias.trim();
      if (trimmed.isEmpty) continue;
      try {
        final queue = registry.queueForAlias(trimmed).name;
        final defined = registry.config.queues.containsKey(queue);
        if (!defined) {
          throw const FormatException('undefined queue');
        }
        if (seen.add(queue)) {
          resolved.add(queue);
        }
      } on FormatException {
        throw StateError(
          'Queue "$trimmed" is not defined in the routing configuration.',
        );
      }
    }
    if (resolved.isEmpty) {
      throw StateError('Worker subscription must include at least one queue.');
    }
    return resolved;
  }

  List<String> _resolveBroadcasts(List<String>? requested) {
    if (requested == null || requested.isEmpty) return const [];
    final seen = <String>{};
    final resolved = <String>[];
    for (final channel in requested) {
      final trimmed = channel.trim();
      if (trimmed.isEmpty) continue;
      final definition = registry.broadcast(trimmed);
      if (definition == null) {
        throw StateError(
          'Broadcast channel "$trimmed" is not defined in the routing configuration.',
        );
      }
      final name = definition.name;
      if (seen.add(name)) {
        resolved.add(name);
      }
    }
    return resolved;
  }
}

/// Convenience helper combining [StemConfig] defaults with optional
/// overrides to produce a [RoutingSubscription].
RoutingSubscription buildWorkerSubscription({
  required StemConfig config,
  required RoutingRegistry registry,
  List<String>? queueOverrides,
  List<String>? broadcastOverrides,
}) {
  final builder = WorkerSubscriptionBuilder(
    registry: registry,
    defaultQueue: config.defaultQueue,
  );
  final queues = queueOverrides != null && queueOverrides.isNotEmpty
      ? queueOverrides
      : (config.workerQueues.isNotEmpty ? config.workerQueues : null);
  final broadcasts = broadcastOverrides != null && broadcastOverrides.isNotEmpty
      ? broadcastOverrides
      : (config.workerBroadcasts.isNotEmpty ? config.workerBroadcasts : null);
  return builder.build(queues: queues, broadcasts: broadcasts);
}
