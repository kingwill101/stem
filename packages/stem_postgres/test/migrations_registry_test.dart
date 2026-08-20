import 'package:stem_postgres/src/database/migrations.dart';
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
      expect(ids.first, contains('m_20251227071920_stem'));
      expect(ids, contains(contains('m_20260819090000_add_task_outbox')));
      expect(
        ids,
        contains(contains('m_20260819100000_add_rate_limit_buckets')),
      );
      expect(
        ids,
        contains(contains('m_20260820110000_add_lock_fencing_tokens')),
      );
    },
  );
}
