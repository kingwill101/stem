import 'dart:io';

import 'tls.dart';

class DashboardConfig {
  DashboardConfig({
    required this.brokerUrl,
    required this.resultBackendUrl,
    required this.namespace,
    required this.tls,
  });

  factory DashboardConfig.fromEnvironment(Map<String, String> environment) {
    final broker = environment['STEM_BROKER_URL']?.trim().isNotEmpty == true
        ? environment['STEM_BROKER_URL']!.trim()
        : 'redis://127.0.0.1:6379/0';
    final backend =
        environment['STEM_RESULT_BACKEND_URL']?.trim().isNotEmpty == true
        ? environment['STEM_RESULT_BACKEND_URL']!.trim()
        : broker;
    final namespace =
        environment['STEM_DASHBOARD_NAMESPACE']?.trim().isNotEmpty == true
        ? environment['STEM_DASHBOARD_NAMESPACE']!.trim()
        : environment['STEM_NAMESPACE']?.trim().isNotEmpty == true
        ? environment['STEM_NAMESPACE']!.trim()
        : 'stem';
    return DashboardConfig(
      brokerUrl: broker,
      resultBackendUrl: backend,
      namespace: namespace,
      tls: TlsConfig.fromEnvironment(environment),
    );
  }

  factory DashboardConfig.load() =>
      DashboardConfig.fromEnvironment(Platform.environment);

  final String brokerUrl;
  final String resultBackendUrl;
  final String namespace;
  final TlsConfig tls;
}
