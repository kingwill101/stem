import 'dart:convert';

import 'package:ansicolor/ansicolor.dart';
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
    StemLogFormat.pretty => _StemPrettyLogFormatter(settings: settings),
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

class _StemPrettyLogFormatter extends LogMessageFormatter {
  _StemPrettyLogFormatter({super.settings});

  static final AnsiPen _keyPen = AnsiPen()..blue(bold: true);
  static final AnsiPen _timestampPen = AnsiPen()..blue();
  static final AnsiPen _contextKeyPen = AnsiPen()..magenta(bold: true);
  static final AnsiPen _prefixPen = AnsiPen()..cyan();
  static final AnsiPen _stackTracePen = AnsiPen()..red();

  @override
  String format(LogRecord record) {
    final levelPen = _levelPen(record.level);
    final parts = <String>[];

    if (settings.includeTimestamp) {
      final timestamp = settings.formatTimestamp(record.time);
      parts.add(
        '${_keyPen('time')}=${_timestampPen(_formatLogfmtValue(timestamp))}',
      );
    }

    if (settings.includeLevel) {
      parts.add(
        '${_keyPen('level')}='
        '${levelPen(_formatLogfmtValue(record.level.name))}',
      );
    }

    if (settings.includePrefix && record.context.has('prefix')) {
      final prefix = record.context.get('prefix');
      parts.add(
        '${_keyPen('prefix')}=${_prefixPen(_formatLogfmtValue(prefix))}',
      );
    }

    final formattedMessage = _interpolateStemMessage(
      record.message,
      record.context,
    );
    parts.add('${_keyPen('msg')}=${_formatLogfmtValue(formattedMessage)}');

    final contextData = settings.includeHidden
        ? record.context.all()
        : record.context.visible();
    if (settings.includeContext && contextData.isNotEmpty) {
      final contextEntries = Map<String, dynamic>.from(contextData);
      if (settings.includePrefix) {
        contextEntries.remove('prefix');
      }
      final flattened = _flattenLogfmtContext(contextEntries);
      for (final entry in flattened.entries) {
        parts.add(
          '${_contextKeyPen(_formatLogfmtKey(entry.key))}'
          '=${_formatLogfmtValue(entry.value)}',
        );
      }
    }

    if (record.stackTraceProvided && record.stackTrace != null) {
      parts.add(
        '${_keyPen('stackTrace')}='
        '${_stackTracePen(_formatLogfmtValue(record.stackTrace.toString()))}',
      );
    }

    return parts.join(' ');
  }

  AnsiPen _levelPen(Level level) {
    return switch (level) {
      Level.debug => AnsiPen()..blue(),
      Level.info => AnsiPen()..green(),
      Level.notice => AnsiPen()..cyan(),
      Level.warning => AnsiPen()..yellow(),
      Level.error => AnsiPen()..red(),
      Level.alert || Level.emergency => AnsiPen()..red(bold: true),
      _ => AnsiPen()..white(),
    };
  }
}

String _interpolateStemMessage(String message, Context context) {
  var resolved = message;
  final placeholderPattern = RegExp(r'\{([^}]+)\}');
  final matches = placeholderPattern.allMatches(resolved).toList();

  for (final match in matches) {
    final rawKey = match.group(1)!;
    final value = _dotLookup(context.all(), rawKey)?.toString();
    if (value == null) continue;
    if (!resolved.contains('{$rawKey}')) continue;
    resolved = resolved.replaceAll('{$rawKey}', value);
  }

  return resolved;
}

Object? _dotLookup(Map<String, dynamic> source, String key) {
  final segments = key.split('.');
  Object? current = source;
  for (final segment in segments) {
    if (current is! Map) return null;
    current = current[segment];
  }
  return current;
}

final _logfmtKeyChar = RegExp('[A-Za-z0-9_.:-]');

String _formatLogfmtKey(String key) {
  if (key.isEmpty) {
    return 'context';
  }
  final buffer = StringBuffer();
  for (final rune in key.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_logfmtKeyChar.hasMatch(char) ? char : '_');
  }
  return buffer.toString();
}

String _formatLogfmtValue(Object? value) {
  final raw = _stringifyLogfmtValue(value);
  if (_needsLogfmtQuoting(raw)) {
    return '"${_escapeLogfmt(raw)}"';
  }
  return raw;
}

Map<String, dynamic> _flattenLogfmtContext(
  Map<String, dynamic> context, {
  String prefix = '',
}) {
  final flattened = <String, dynamic>{};

  void addEntry(String key, dynamic value) {
    final fullKey = prefix.isEmpty ? key : '$prefix$key';
    if (value is Map) {
      value.forEach((nestedKey, nestedValue) {
        final nestedKeyString = nestedKey?.toString() ?? '';
        final combinedKey = fullKey.isEmpty
            ? nestedKeyString
            : '$fullKey.$nestedKeyString';
        flattened.addAll(
          _flattenLogfmtContext(<String, dynamic>{combinedKey: nestedValue}),
        );
      });
      return;
    }
    flattened[fullKey] = value;
  }

  context.forEach(addEntry);
  return flattened;
}

String _stringifyLogfmtValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is DateTime) return value.toIso8601String();
  if (value is Map || value is Iterable) {
    try {
      return jsonEncode(value);
    } on Object {
      return value.toString();
    }
  }
  return value.toString();
}

bool _needsLogfmtQuoting(String value) {
  if (value.isEmpty) return true;
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
      return true;
    }
    if (code == 0x22 || code == 0x5C || code == 0x3D) {
      return true;
    }
  }
  return false;
}

String _escapeLogfmt(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
