import 'package:contextual/contextual.dart';

/// Shared logger configured with console output suitable for worker
/// diagnostics.
final stemLogger = Logger()
  ..addChannel(
    'console',
    ConsoleLogDriver(),
    formatter: PlainTextLogFormatter(
      settings: FormatterSettings(
        includePrefix: false,
      ),
    ),
  );

/// Sets the minimum log [level] for the shared [stemLogger].
void configureStemLogging({Level level = Level.info}) {
  stemLogger.setLevel(level);
}
