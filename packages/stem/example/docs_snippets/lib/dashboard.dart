import 'dart:io';

import 'package:stem/stem.dart';

void main() {
  logDashboardConfig();
  logDashboardOverrides();
  logDashboardTls();
}

void logDashboardConfig() {
  // #region dashboard-config
  final config = StemConfig.fromEnvironment({
    'STEM_BROKER_URL': 'redis://127.0.0.1:6379/0',
    'STEM_RESULT_BACKEND_URL': 'redis://127.0.0.1:6379/1',
  });

  stdout.writeln(
    'Dashboard config broker=${config.brokerUrl} '
    'backend=${config.resultBackendUrl ?? config.brokerUrl}',
  );
  // #endregion dashboard-config
}

void logDashboardOverrides() {
  // #region dashboard-overrides
  final config = StemConfig.fromEnvironment({
    'STEM_BROKER_URL': 'redis://127.0.0.1:6379/0',
    'STEM_RESULT_BACKEND_URL': 'redis://127.0.0.1:6379/1',
    'STEM_DEFAULT_QUEUE': 'critical',
    'STEM_PREFETCH_MULTIPLIER': '4',
  });

  stdout.writeln(
    'Dashboard defaults queue=${config.defaultQueue} '
    'prefetch=${config.prefetchMultiplier}',
  );
  // #endregion dashboard-overrides
}

void logDashboardTls() {
  // #region dashboard-tls
  final config = StemConfig.fromEnvironment({
    'STEM_BROKER_URL': 'rediss://redis.example.com:6380/0',
    'STEM_TLS_CA_CERT': '/etc/ssl/certs/ca.pem',
    'STEM_TLS_ALLOW_INSECURE': 'false',
  });

  stdout.writeln(
    'Dashboard TLS enabled=${config.tls.isEnabled} '
    'allowInsecure=${config.tls.allowInsecure}',
  );
  // #endregion dashboard-tls
}
