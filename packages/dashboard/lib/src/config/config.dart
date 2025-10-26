import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_cli/stem_cli.dart';

class DashboardConfig {
  DashboardConfig._({
    required this.environment,
    required this.stem,
    required this.namespace,
    required this.routing,
  });

  factory DashboardConfig.fromEnvironment(Map<String, String> environment) {
    final stemConfig = StemConfig.fromEnvironment(environment);
    final env = Map<String, String>.from(environment);
    final namespace = env['STEM_DASHBOARD_NAMESPACE']?.trim().isNotEmpty == true
        ? env['STEM_DASHBOARD_NAMESPACE']!.trim()
        : env['STEM_NAMESPACE']?.trim().isNotEmpty == true
        ? env['STEM_NAMESPACE']!.trim()
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

  factory DashboardConfig.load() =>
      DashboardConfig.fromEnvironment(Platform.environment);

  final Map<String, String> environment;
  final StemConfig stem;
  final String namespace;
  final RoutingRegistry routing;

  String get brokerUrl => stem.brokerUrl;
  String? get resultBackendUrl => stem.resultBackendUrl;
  TlsConfig get tls => stem.tls;
}
