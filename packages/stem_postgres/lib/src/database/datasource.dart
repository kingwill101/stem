import 'package:ormed/ormed.dart';
import 'package:stem_postgres/orm_registry.g.dart';
import 'package:ormed_postgres/ormed_postgres.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource() {
  ensurePostgresDriverRegistration();

  final config = loadOrmConfig();
  return DataSource.fromConfig(
    config,
    registry: bootstrapOrm(),
  );
}
