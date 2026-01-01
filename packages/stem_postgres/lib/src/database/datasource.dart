import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem_postgres/orm_registry.g.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource({
  String? connectionString,
  bool logging = false,
}) {
  ensurePostgresDriverRegistration();

  final config = (connectionString != null && connectionString.isNotEmpty)
      ? OrmProjectConfig(
          connections: {
            'default': ConnectionDefinition(
              name: 'default',
              driver: DriverConfig(
                type: 'postgres',
                options: {
                  'url': connectionString,
                  if (logging) 'logging': true,
                },
              ),
              migrations: MigrationSection(
                directory: 'lib/src/database/migrations',
                registry: 'lib/src/database/migrations.dart',
                ledgerTable: 'orm_migrations',
                schemaDump: 'database/schema.sql',
              ),
              seeds: SeedSection(
                directory: 'lib/src/database/seeders',
                registry: 'lib/src/database/seeders.dart',
              ),
            ),
          },
          activeConnectionName: 'default',
        )
      : loadOrmConfig();
  return DataSource.fromConfig(config, registry: bootstrapOrm());
}
