import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryScheduleStore versioning', () {
    test('increments version on upsert and markExecuted', () async {
      final store = InMemoryScheduleStore();
      final entry = ScheduleEntry(
        id: 'demo',
        taskName: 'noop',
        queue: 'default',
        spec: IntervalScheduleSpec(every: const Duration(minutes: 1)),
      );

      await store.upsert(entry);
      var stored = await store.get('demo');
      expect(stored, isNotNull);
      expect(stored!.version, equals(1));

      final updated = stored.copyWith(queue: 'critical');
      await store.upsert(updated);
      stored = await store.get('demo');
      expect(stored, isNotNull);
      expect(stored!.queue, equals('critical'));
      expect(stored.version, equals(2));

      final scheduledFor = DateTime.now().toUtc();
      final executedAt = scheduledFor.add(const Duration(seconds: 5));
      await store.markExecuted(
        'demo',
        scheduledFor: scheduledFor,
        executedAt: executedAt,
      );

      stored = await store.get('demo');
      expect(stored, isNotNull);
      expect(stored!.version, equals(3));
    });

    test('throws conflict when version mismatches', () async {
      final store = InMemoryScheduleStore();
      final entry = ScheduleEntry(
        id: 'demo',
        taskName: 'noop',
        queue: 'default',
        spec: IntervalScheduleSpec(every: const Duration(minutes: 1)),
      );

      await store.upsert(entry);
      final stored = await store.get('demo');
      expect(stored, isNotNull);
      expect(stored!.version, equals(1));

      final stale = stored.copyWith(version: 0, queue: 'stale');
      expect(
        () => store.upsert(stale),
        throwsA(isA<ScheduleConflictException>()),
      );
    });
  });
}
