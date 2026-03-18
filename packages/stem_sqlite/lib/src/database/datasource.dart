import 'package:contextual/contextual.dart' as contextual;
import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart' show stemLogger;
import 'package:stem_sqlite/orm_registry.g.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource({
  bool logging = false,
  contextual.Logger? logger,
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
  contextual.Logger? logger,
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
  return DataSource(dataSourceOptions.copyWith(logger: logger));
}
