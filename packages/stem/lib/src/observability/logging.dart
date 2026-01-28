import 'package:contextual/contextual.dart';

Logger _buildStemLogger() {
  return Logger()..addChannel(
    'console',
    ConsoleLogDriver(),
    formatter: PlainTextLogFormatter(
      settings: FormatterSettings(
        includePrefix: false,
      ),
    ),
  );
}

Logger _stemLogger = _buildStemLogger();

/// Shared logger configured with console output suitable for worker
/// diagnostics.
Logger get stemLogger => _stemLogger;

/// Replaces the shared [stemLogger] instance used across Stem packages.
void setStemLogger(Logger logger) {
  _stemLogger = logger;
}

/// Sets the minimum log [level] for the shared [stemLogger].
void configureStemLogging({Level level = Level.info}) {
  stemLogger.setLevel(level);
}
