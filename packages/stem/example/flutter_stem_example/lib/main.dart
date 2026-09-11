import 'package:flutter/material.dart';
import 'package:stem/observability.dart';

import 'src/app.dart';
import 'src/demo_workflows.dart';
import 'src/demo_workers.dart';

export 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureStemLogging(
    level: StemLogLevel.debug,
    format: StemLogFormat.plain,
    enableConsole: true,
  );
  stemLogger.info('Flutter example booting');
  runApp(
    StemFlutterExampleApp(
      attachWorkflows: attachDemoWorkflows,
      createAdditionalWorkers: createAdditionalDemoWorkers,
    ),
  );
}
