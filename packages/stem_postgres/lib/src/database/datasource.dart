import 'package:contextual/contextual.dart' as contextual;
import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem/stem.dart' show stemLogger;
import 'package:stem_postgres/orm_registry.g.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource({
  String? connectionString,
  bool logging = false,
  contextual.Logger? logger,
}) {
  if (connectionString != null && connectionString.isNotEmpty) {
    final options = bootstrapOrm()
        .postgresDataSourceOptionsFromEnv(
          environment: {'DATABASE_URL': connectionString},
          logging: logging,
        )
        .copyWith(logger: logger ?? stemLogger);
    return DataSource(options);
  }

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
  final url = options['url']?.toString();
  final dataSourceOptions = (url != null && url.isNotEmpty)
      ? registry.postgresDataSourceOptionsFromEnv(
          environment: {
            'DATABASE_URL': url,
            if (options['sslmode'] case final Object sslmode)
              'DB_SSLMODE': sslmode.toString(),
            if (options['timezone'] case final Object timezone)
              'DB_TIMEZONE': timezone.toString(),
            if (options['applicationName'] case final Object appName)
              'DB_APP_NAME': appName.toString(),
          },
          name: config.activeConnectionName,
          logging: options['logging'] == true,
          tablePrefix: options['table_prefix']?.toString() ?? '',
          defaultSchema:
              options['default_schema']?.toString() ??
              options['schema']?.toString() ??
              'public',
        )
      : registry.postgresDataSourceOptions(
          host: options['host']?.toString() ?? 'localhost',
          port: switch (options['port']) {
            final int value => value,
            final String value => int.tryParse(value) ?? 5432,
            _ => 5432,
          },
          database: options['database']?.toString() ?? 'postgres',
          username:
              options['username']?.toString() ??
              options['user']?.toString() ??
              'postgres',
          password: options['password']?.toString(),
          sslmode: options['sslmode']?.toString() ?? 'disable',
          timezone: options['timezone']?.toString() ?? 'UTC',
          applicationName: options['applicationName']?.toString(),
          name: config.activeConnectionName,
          logging: options['logging'] == true,
          tablePrefix: options['table_prefix']?.toString() ?? '',
          defaultSchema:
              options['default_schema']?.toString() ??
              options['schema']?.toString() ??
              'public',
        );
  return DataSource(dataSourceOptions.copyWith(logger: logger));
}
