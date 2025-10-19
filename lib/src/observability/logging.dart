import 'package:logging/logging.dart';

final stemLogger = Logger('stem');

void configureStemLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String();
    final error = record.error != null ? ' error=${record.error}' : '';
    final stack = record.stackTrace != null ? '\n${record.stackTrace}' : '';
    // ignore: avoid_print
    print(
      '[${record.level.name}] $time ${record.loggerName}: ${record.message}$error$stack',
    );
  });
}
