import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/observability.dart' show StemLogger, stemLogger;
import 'package:stem_sqlite/src/database/orm_registry.g.dart';
import 'package:stem_sqlite/src/database/stem_orm_logger.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource({
  bool logging = false,
  StemLogger? logger,
}) {
  var config = loadOrmConfig();
  if (logging) {
    config = config.updateActiveConnection(
      driver: config.driver.copyWith(
        options: {...config.driver.options, 'logging': true},
      ),
    );
  }
  return createDataSourceFromConfig(config, logger: logger ?? stemLogger);
}

/// Creates a new DataSource instance using a resolved ORM project config.
DataSource createDataSourceFromConfig(
  OrmProjectConfig config, {
  StemLogger? logger,
}) {
  final registry = bootstrapOrm();
  final options = Map<String, Object?>.from(config.driver.options);
  final database =
      options['database']?.toString() ??
      options['path']?.toString() ??
      'database.sqlite';
  final dataSourceOptions = database == ':memory:'
      ? registry.sqliteInMemoryDataSourceOptions(
          name: config.activeConnectionName,
          logging: options['logging'] == true,
          tablePrefix: options['table_prefix']?.toString() ?? '',
          defaultSchema: options['default_schema']?.toString(),
        )
      : registry.sqliteFileDataSourceOptions(
          path: database,
          name: config.activeConnectionName,
          logging: options['logging'] == true,
          tablePrefix: options['table_prefix']?.toString() ?? '',
          defaultSchema: options['default_schema']?.toString(),
        );
  return DataSource(
    dataSourceOptions.copyWith(
      logger: createOrmLogger(logger ?? stemLogger),
    ),
  );
}
