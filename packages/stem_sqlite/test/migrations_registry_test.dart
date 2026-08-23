import 'package:stem_sqlite/src/database/migrations.dart';
import 'package:test/test.dart';

void main() {
  test(
    'migration registry is ordered, unique, and retains release history',
    () {
      final migrations = buildMigrations();
      final ids = migrations
          .map((migration) => migration.id.toString())
          .toList();

      expect(ids, isNotEmpty);
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, orderedEquals([...ids]..sort()));
      expect(ids.first, contains('m_20251222070816_create_stem_tables'));
      expect(ids, contains(contains('m_20260224103000_add_revoke_store')));
    },
  );
}
