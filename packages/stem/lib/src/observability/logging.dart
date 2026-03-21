import 'package:contextual/contextual.dart';

/// Available output formats for the shared Stem logger.
enum StemLogFormat {
  /// Plain logfmt-style output without ANSI color codes.
  plain,

  /// Colored terminal output intended for interactive local development.
  pretty,
}

/// Creates a formatter matching the shared Stem logging presets.
LogMessageFormatter createStemLogFormatter(StemLogFormat format) {
  final settings = FormatterSettings(includePrefix: false);
  return switch (format) {
    StemLogFormat.pretty => PrettyLogFormatter(settings: settings),
    StemLogFormat.plain => PlainTextLogFormatter(settings: settings),
  };
}

/// Creates a logger configured the same way Stem configures its shared logger.
Logger createStemLogger({
  Level level = Level.info,
  StemLogFormat format = StemLogFormat.pretty,
  bool enableConsole = true,
}) {
  final logger = Logger(
    formatter: createStemLogFormatter(format),
    defaultChannelEnabled: false,
  )..setLevel(level);
  if (enableConsole) {
    logger.addChannel('console', ConsoleLogDriver());
  }
  return logger;
}

Logger _stemLogger = createStemLogger();

/// Shared logger configured with console output suitable for worker
/// diagnostics.
Logger get stemLogger => _stemLogger;

/// Replaces the shared [stemLogger] instance used across Stem packages.
void setStemLogger(Logger logger) {
  _stemLogger = logger;
}

/// Builds a shared context payload for Stem log entries.
Map<String, Object?> stemContextFields({
  required String component,
  required String subsystem,
  Map<String, Object?>? fields,
}) {
  return {
    'component': component,
    'subsystem': subsystem,
    ...?fields,
  };
}

/// Creates a [Context] for the shared Stem logger.
Context stemLogContext({
  required String component,
  required String subsystem,
  Map<String, Object?>? fields,
}) {
  return Context(
    stemContextFields(
      component: component,
      subsystem: subsystem,
      fields: fields,
    ),
  );
}

/// Sets the minimum log [level] for the shared [stemLogger].
void configureStemLogging({
  Level level = Level.info,
  StemLogFormat? format,
}) {
  stemLogger.setLevel(level);
  if (format != null) {
    stemLogger.formatter(createStemLogFormatter(format));
  }
}
