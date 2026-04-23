import 'package:ormed/ormed.dart';

const String _migrationLockName = 'stem_postgres_migrations';

/// Runs [action] while holding a database-scoped Postgres advisory lock.
Future<T> withPostgresMigrationLock<T>(
  DriverAdapter driver,
  Future<T> Function() action,
) async {
  await driver.executeRaw(
    "SELECT pg_advisory_lock(hashtext('$_migrationLockName'));",
  );
  try {
    return await action();
  } finally {
    await driver.executeRaw(
      "SELECT pg_advisory_unlock(hashtext('$_migrationLockName'));",
    );
  }
}
