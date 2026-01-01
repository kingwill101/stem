import 'dart:io';

import 'package:stem/stem.dart';

void main() {
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
