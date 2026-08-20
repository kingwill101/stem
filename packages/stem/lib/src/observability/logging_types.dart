/// Public logging configuration types owned by Stem.
library;

/// Log severity understood by Stem's logging facade.
enum StemLogLevel {
  /// Diagnostic messages useful during local debugging.
  debug,

  /// Normal operational messages.
  info,

  /// Notice-level operational messages.
  notice,

  /// Recoverable or potentially actionable problems.
  warning,

  /// Errors that prevented an operation from completing normally.
  error,

  /// Serious errors requiring attention.
  critical,

  /// Severe failures requiring immediate attention.
  alert,

  /// System-level failures requiring immediate attention.
  emergency,
}

/// Output format used by Stem's built-in logging configuration.
enum StemLogFormat {
  /// Plain logfmt-style output without ANSI color codes.
  plain,

  /// Colored terminal output intended for interactive local development.
  pretty,
}

/// Dependency-neutral facade for emitting Stem log messages.
///
/// The concrete logger and its formatter types are intentionally kept out of
/// Stem's public API. Structured fields should use the `fields` parameter
/// rather than a
/// logging-library context object; pass structured values through the
/// `fields` parameter.
abstract interface class StemLogger {
  /// Emits a debug message.
  void debug(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits an informational message.
  void info(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits a notice message.
  void notice(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits a warning message.
  void warning(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits an error message.
  void error(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits a critical message.
  void critical(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits an alert message.
  void alert(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });

  /// Emits an emergency message.
  void emergency(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  });
}
