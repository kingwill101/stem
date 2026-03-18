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
  ensurePostgresDriverRegistration();
  final registry = bootstrapOrm();

  if (connectionString != null && connectionString.isNotEmpty) {
    final options = registry
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

  return DataSource.fromConfig(
    config,
    registry: registry,
    logger: logger ?? stemLogger,
  );
}
