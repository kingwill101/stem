/// Stable, dependency-neutral logging configuration for Stem.
library;

import 'package:contextual/contextual.dart' as contextual;

import 'package:stem/src/observability/logging.dart' as implementation;
import 'package:stem/src/observability/logging_types.dart';

/// The shared Stem logger facade.
final StemLogger stemLogger = _StemLoggerFacade();

/// Configures Stem's built-in logger without exposing its logging dependency.
void configureStemLogging({
  StemLogLevel level = StemLogLevel.info,
  StemLogFormat format = StemLogFormat.pretty,
  bool enableConsole = true,
}) {
  implementation.configureStemLogging(
    level: _toContextualLevel(level),
    format: format,
    enableConsole: enableConsole,
  );
}

contextual.Level _toContextualLevel(StemLogLevel level) {
  return switch (level) {
    StemLogLevel.debug => contextual.Level.debug,
    StemLogLevel.info => contextual.Level.info,
    StemLogLevel.notice => contextual.Level.notice,
    StemLogLevel.warning => contextual.Level.warning,
    StemLogLevel.error => contextual.Level.error,
    StemLogLevel.critical => contextual.Level.critical,
    StemLogLevel.alert => contextual.Level.alert,
    StemLogLevel.emergency => contextual.Level.emergency,
  };
}

class _StemLoggerFacade implements StemLogger {
  contextual.Context? _context(Map<String, Object?>? fields) {
    return fields == null ? null : contextual.Context(fields);
  }

  @override
  void debug(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.debug(message, _context(fields), stackTrace);
  }

  @override
  void info(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.info(message, _context(fields), stackTrace);
  }

  @override
  void notice(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.notice(message, _context(fields), stackTrace);
  }

  @override
  void warning(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.warning(message, _context(fields), stackTrace);
  }

  @override
  void error(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.error(message, _context(fields), stackTrace);
  }

  @override
  void critical(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.critical(message, _context(fields), stackTrace);
  }

  @override
  void alert(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.alert(message, _context(fields), stackTrace);
  }

  @override
  void emergency(
    Object message, {
    Map<String, Object?>? fields,
    StackTrace? stackTrace,
  }) {
    implementation.stemLogger.emergency(message, _context(fields), stackTrace);
  }
}
