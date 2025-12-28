import 'package:ormed_cli/runtime.dart';
import 'package:ormed/ormed.dart';
import 'package:stem_sqlite/orm_registry.g.dart';

import 'seeders/database_seeder.dart';
// <ORM-SEED-IMPORTS>
// </ORM-SEED-IMPORTS>

final List<SeederRegistration> _seeders = <SeederRegistration>[
// <ORM-SEED-REGISTRY>
  SeederRegistration(
    name: 'AppDatabaseSeeder',
    factory: (connection) => AppDatabaseSeeder(connection),
  ),
// </ORM-SEED-REGISTRY>
];

Future<void> runProjectSeeds(
  OrmConnection connection, {
  List<String>? names,
  bool pretend = false,
}) => runSeedRegistryOnConnection(
      connection,
      _seeders,
      names: names,
      pretend: pretend,
      beforeRun: (conn) => bootstrapOrm(registry: conn.context.registry),
    );

Future<void> main(List<String> args) => runSeedRegistryEntrypoint(
      args: args,
      seeds: _seeders,
      beforeRun: (connection) =>
          bootstrapOrm(registry: connection.context.registry),
    );
