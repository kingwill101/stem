import 'package:ormed/ormed.dart';

/// Root seeder executed by `orm seed` and `orm migrate --seed`.
class AppDatabaseSeeder extends DatabaseSeeder {
  /// Creates a seeder bound to the provided connection.
  AppDatabaseSeeder(super.connection);

  /// Seeds initial application data such as baseline tenants or policies.
  /// Replace the example calls below with your project-specific seeds.
  @override
  Future<void> run() async {
    // No default seeds are installed by stem; add yours here as needed.
    // Example:
    // await seed<User>([
    //   {'name': 'Admin User', 'email': 'admin@example.com'},
    // ]);
    // Or invoke nested seeders:
    // await call([UserSeeder.new, PostSeeder.new]);
  }
}
