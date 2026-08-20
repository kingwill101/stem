import 'package:ormed/ormed.dart';

/// Root seeder executed by `orm seed` and `orm migrate --seed`.
class AppDatabaseSeeder extends DatabaseSeeder {
  /// Creates a seeder bound to the provided connection.
  AppDatabaseSeeder(super.connection);

  @override
  Future<void> run() async {
    // No default seeds are installed by stem; add application-specific data
    // from the consuming service instead.
    // Examples:
    // await seed<User>([
    //   {'name': 'Admin User', 'email': 'admin@example.com'},
    // ]);
    //
    // Or call other seeders:
    // await call([UserSeeder.new, PostSeeder.new]);
  }
}
