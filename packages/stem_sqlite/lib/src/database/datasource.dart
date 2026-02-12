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
  ensureSqliteDriverRegistration();

  var config = loadOrmConfig();
  if (logging) {
    config = config.updateActiveConnection(
      driver: config.driver.copyWith(
        options: {...?config.driver.options, 'logging': true},
      ),
    );
  }
  return DataSource.fromConfig(
    config,
    registry: bootstrapOrm(),
    logger: logger ?? stemLogger,
  );
}
