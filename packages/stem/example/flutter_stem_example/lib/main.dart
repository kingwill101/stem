import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'src/app.dart';

export 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureStemLogging(
    level: Level.debug,
    format: StemLogFormat.plain,
    enableConsole: true,
  );
  stemLogger.info('Flutter example booting');
  runApp(const StemFlutterExampleApp());
}
