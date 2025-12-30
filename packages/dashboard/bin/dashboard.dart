import 'dart:io';

import 'package:stem_dashboard/dashboard.dart';

Future<void> main(List<String> args) async {
  final host = Platform.environment['DASHBOARD_HOST']?.trim();
  final portRaw = Platform.environment['DASHBOARD_PORT']?.trim();
  final echoRaw = Platform.environment['DASHBOARD_ECHO_ROUTES']?.trim();

  final resolvedHost = host != null && host.isNotEmpty ? host : '127.0.0.1';
  final resolvedPort = int.tryParse(portRaw ?? '') ?? 3080;
  final echoRoutes = _parseBool(echoRaw) ?? false;

  // The service will be created from environment config in runDashboardServer
  await runDashboardServer(
    options: DashboardServerOptions(
      host: resolvedHost,
      port: resolvedPort,
      echoRoutes: echoRoutes,
    ),
    service: null, // Will use config from environment
  );
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}
