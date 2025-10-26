import 'dart:io';

import 'package:stem_dashboard/dashboard.dart';

Future<void> main(List<String> args) async {
  String? sqlitePath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--sqlite' || arg == '-s') {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing database path after $arg');
        exitCode = 64;
        return;
      }
      sqlitePath = args[++i];
    } else {
      stderr.writeln('Unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final host = Platform.environment['DASHBOARD_HOST']?.trim();
  final portRaw = Platform.environment['DASHBOARD_PORT']?.trim();
  final echoRaw = Platform.environment['DASHBOARD_ECHO_ROUTES']?.trim();

  final resolvedHost = host != null && host.isNotEmpty ? host : '127.0.0.1';
  final resolvedPort = int.tryParse(portRaw ?? '') ?? 3080;
  final echoRoutes = _parseBool(echoRaw) ?? false;

  SqliteDashboardService? sqliteService;
  if (sqlitePath != null) {
    try {
      sqliteService = await SqliteDashboardService.connect(File(sqlitePath));
    } on StateError catch (error) {
      stderr.writeln('[stem-dashboard] ${error.message}');
      exitCode = 64;
      return;
    }
  }

  await runDashboardServer(
    options: DashboardServerOptions(
      host: resolvedHost,
      port: resolvedPort,
      echoRoutes: echoRoutes,
    ),
    service: sqliteService,
  );

  await sqliteService?.close();
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
