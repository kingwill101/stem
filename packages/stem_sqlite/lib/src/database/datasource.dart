import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem_sqlite/orm_registry.g.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource() {
  ensureSqliteDriverRegistration();

  final config = loadOrmConfig();
  return DataSource.fromConfig(config, registry: bootstrapOrm());
}
