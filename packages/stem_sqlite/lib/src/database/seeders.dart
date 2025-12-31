// Ignoring unreachable_from_main because tooling imports use runProjectSeeds.
// ignore_for_file: unreachable_from_main

import 'package:ormed/ormed.dart';
import 'package:stem_sqlite/orm_registry.g.dart';
import 'package:stem_sqlite/src/database/seed_runtime.dart';
import 'package:stem_sqlite/src/database/seeders/database_seeder.dart';
// <ORM-SEED-IMPORTS>
// </ORM-SEED-IMPORTS>

final List<SeederRegistration> _seeders = <SeederRegistration>[
  // <ORM-SEED-REGISTRY>
  const SeederRegistration(
    name: 'AppDatabaseSeeder',
    factory: AppDatabaseSeeder.new,
  ),
  // </ORM-SEED-REGISTRY>
];

/// Runs registered seeders programmatically.
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

/// CLI entrypoint for running registered seeders.
Future<void> main(List<String> args) => runSeedRegistryEntrypoint(
  args: args,
  seeds: _seeders,
  beforeRun: (connection) =>
      bootstrapOrm(registry: connection.context.registry),
);
