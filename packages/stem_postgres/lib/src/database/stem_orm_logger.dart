import 'package:contextual/contextual.dart' as contextual;
import 'package:stem/observability.dart' show StemLogger;

/// Adapts Stem's dependency-neutral logger to the ORM's logger contract.
contextual.Logger createOrmLogger(StemLogger logger) {
  final ormLogger =
      contextual.Logger(
        level: contextual.Level.debug,
        defaultChannelEnabled: false,
      )..setListener((entry) {
        final record = entry.record;
        final fields = record.context.all().cast<String, Object?>();
        switch (record.level) {
          case contextual.Level.debug:
            logger.debug(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.info:
            logger.info(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.notice:
            logger.notice(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.warning:
            logger.warning(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.error:
            logger.error(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.critical:
            logger.critical(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.alert:
            logger.alert(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
          case contextual.Level.emergency:
            logger.emergency(
              record.message,
              fields: fields,
              stackTrace: record.stackTrace,
            );
        }
      });
  return ormLogger;
}
