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

    return DashboardConfig._(
      environment: Map.unmodifiable(env),
      stem: stemConfig,
      namespace: namespace,
      routing: routing,
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

  /// Broker URL resolved from the underlying Stem config.
  String get brokerUrl => stem.brokerUrl;

  /// Result backend URL resolved from the underlying Stem config, if set.
  String? get resultBackendUrl => stem.resultBackendUrl;

  /// TLS configuration resolved from the underlying Stem config.
  TlsConfig get tls => stem.tls;
}
