import 'package:ormed/ormed.dart';
import 'package:stem_postgres/orm_registry.g.dart' as g;
import 'package:stem_postgres/src/database/seed_runtime.dart';
import 'package:stem_postgres/src/database/seeders/database_seeder.dart';
// <ORM-SEED-IMPORTS>
// </ORM-SEED-IMPORTS>

/// Registered seeders for this project.
///
/// Used by `ormed seed` command and can be imported for programmatic seeding.
final List<SeederRegistration> seeders = <SeederRegistration>[
  // <ORM-SEED-REGISTRY>
  const SeederRegistration(
    name: 'AppDatabaseSeeder',
    factory: AppDatabaseSeeder.new,
  ),
  // </ORM-SEED-REGISTRY>
];

/// Run project seeders on the given connection.
///
/// Example:
/// ```dart
/// await runProjectSeeds(connection);
/// await runProjectSeeds(connection, names: ['UserSeeder']);
/// ```
// Exposed as a library API even though this file includes a main entrypoint.
// ignore: unreachable_from_main
Future<void> runProjectSeeds(
  OrmConnection connection, {
  List<String>? names,
  bool pretend = false,
}) async {
  g.bootstrapOrm(registry: connection.context.registry);
  await SeederRunner().run(
    connection: connection,
    seeders: seeders,
    names: names,
    pretend: pretend,
  );
}

Future<void> main(List<String> args) => runSeedRegistryEntrypoint(
  args: args,
  seeds: seeders,
  beforeRun: (connection) =>
      g.bootstrapOrm(registry: connection.context.registry),
);
