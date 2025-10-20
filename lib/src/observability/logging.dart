import 'package:contextual/contextual.dart';

final stemLogger = Logger()
  ..addChannel(
    'console',
    ConsoleLogDriver(),
    formatter: PlainTextLogFormatter(
      settings: FormatterSettings(
        includeTimestamp: true,
        includeLevel: true,
        includeContext: true,
        includePrefix: false,
      ),
    ),
  );

void configureStemLogging({Level level = Level.info}) {
  stemLogger.setLevel(level);
}
