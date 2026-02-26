import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_cli/stem_cli.dart';

/// Configuration snapshot for the dashboard runtime.
class DashboardConfig {
  /// Creates a dashboard config from resolved environment and routing values.
  DashboardConfig._({
    required this.environment,
    required this.stem,
    required this.namespace,
    required this.routing,
    required this.alertWebhookUrls,
    required this.alertBacklogThreshold,
    required this.alertFailedTaskThreshold,
    required this.alertOfflineWorkerThreshold,
    required this.alertCooldown,
  });

  /// Loads a dashboard config from the provided environment map.
  factory DashboardConfig.fromEnvironment(Map<String, String> environment) {
    final stemConfig = StemConfig.fromEnvironment(environment);
    final env = Map<String, String>.from(environment);
    final dashboardNamespace = env['STEM_DASHBOARD_NAMESPACE']?.trim();
    final stemNamespace = env['STEM_NAMESPACE']?.trim();
    final namespace =
        (dashboardNamespace != null && dashboardNamespace.isNotEmpty)
        ? dashboardNamespace
        : (stemNamespace != null && stemNamespace.isNotEmpty)
        ? stemNamespace
        : 'stem';
    env['STEM_NAMESPACE'] ??= namespace;
    final routing = RoutingConfigLoader(
      StemRoutingContext.fromConfig(stemConfig),
    ).load();
    final webhookUrls = _parseCsv(
      env['STEM_DASHBOARD_ALERT_WEBHOOK_URLS'] ??
          env['STEM_DASHBOARD_WEBHOOK_URLS'],
    );
    final backlogThreshold = _parsePositiveInt(
      env['STEM_DASHBOARD_ALERT_BACKLOG_THRESHOLD'],
      fallback: 500,
    );
    final failedThreshold = _parsePositiveInt(
      env['STEM_DASHBOARD_ALERT_FAILED_TASK_THRESHOLD'],
      fallback: 25,
    );
    final offlineThreshold = _parsePositiveInt(
      env['STEM_DASHBOARD_ALERT_OFFLINE_WORKER_THRESHOLD'],
      fallback: 1,
    );
    final cooldown = _parseDuration(
      env['STEM_DASHBOARD_ALERT_COOLDOWN'],
      fallback: const Duration(minutes: 5),
    );

    return DashboardConfig._(
      environment: Map.unmodifiable(env),
      stem: stemConfig,
      namespace: namespace,
      routing: routing,
      alertWebhookUrls: webhookUrls,
      alertBacklogThreshold: backlogThreshold,
      alertFailedTaskThreshold: failedThreshold,
      alertOfflineWorkerThreshold: offlineThreshold,
      alertCooldown: cooldown,
    );
  }

  /// Loads a dashboard config from the current process environment.
  factory DashboardConfig.load() =>
      DashboardConfig.fromEnvironment(Platform.environment);

  /// Raw environment variables used to construct this config.
  final Map<String, String> environment;

  /// Stem core configuration derived from [environment].
  final StemConfig stem;

  /// Namespace used to scope dashboard resources.
  final String namespace;

  /// Routing registry resolved for this dashboard session.
  final RoutingRegistry routing;

  /// Alert webhook URLs.
  final List<String> alertWebhookUrls;

  /// Backlog alert threshold.
  final int alertBacklogThreshold;

  /// Failed task alert threshold.
  final int alertFailedTaskThreshold;

  /// Offline worker alert threshold.
  final int alertOfflineWorkerThreshold;

  /// Alert cooldown.
  final Duration alertCooldown;

  /// Broker URL resolved from the underlying Stem config.
  String get brokerUrl => stem.brokerUrl;

  /// Result backend URL resolved from the underlying Stem config, if set.
  String? get resultBackendUrl => stem.resultBackendUrl;

  /// TLS configuration resolved from the underlying Stem config.
  TlsConfig get tls => stem.tls;
}

List<String> _parseCsv(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

int _parsePositiveInt(String? raw, {required int fallback}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed <= 0) return fallback;
  return parsed;
}

Duration _parseDuration(String? raw, {required Duration fallback}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final value = raw.trim();
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(value);
  if (match == null) return fallback;
  final amount = int.tryParse(match.group(1) ?? '');
  if (amount == null || amount <= 0) return fallback;
  switch (match.group(2)) {
    case 'ms':
      return Duration(milliseconds: amount);
    case 's':
      return Duration(seconds: amount);
    case 'm':
      return Duration(minutes: amount);
    case 'h':
      return Duration(hours: amount);
  }
  return fallback;
}
