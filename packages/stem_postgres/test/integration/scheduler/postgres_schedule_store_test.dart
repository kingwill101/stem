import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/stem_schedule_entry.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres schedule store integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip: 'Set STEM_TEST_POSTGRES_URL to run Postgres schedule store tests.',
    );
    return;
  }

  const namespace = 'test_sched';
  late PostgresScheduleStore store;
  late PostgresConnections adminConnections;

  Future<void> clearTables() async {
    await adminConnections.context.query<$StemScheduleEntry>().delete();
  }

  setUp(() async {
    adminConnections = await PostgresConnections.open(
      connectionString: connectionString,
    );
    store = await PostgresScheduleStore.connect(
      connectionString,
      namespace: namespace,
      applicationName: 'stem-postgres-schedule-test',
    );
    await clearTables();
  });

  tearDown(() async {
    await clearTables();
    await store.close();
    await adminConnections.close();
  });

  test('due acquires locks and respects lock expiry', () async {
    final now = DateTime.now().toUtc();
    final entry = ScheduleEntry(
      id: 'sched-1',
      taskName: 'task.example',
      queue: 'default',
      spec: CronScheduleSpec(expression: '* * * * *'),
      nextRunAt: now.subtract(const Duration(seconds: 1)),
    );

    await store.upsert(entry);

    final rows = await adminConnections.context
        .query<$StemScheduleEntry>()
        .get();
    expect(rows, isNotEmpty, reason: 'entry should be persisted');
    final storedNextRun = rows.first.nextRunAt!;
    expect(
      storedNextRun.isBefore(
        DateTime.now().toUtc().add(const Duration(seconds: 1)),
      ),
      isTrue,
      reason: 'next_run_at should be in the past',
    );

    final dueNow = DateTime.now().toUtc();

    final manualDueRows = await adminConnections.context
        .query<$StemScheduleEntry>()
        .where((PredicateBuilder<$StemScheduleEntry> q) {
          q
            ..where('enabled', true, PredicateOperator.equals)
            ..where('nextRunAt', dueNow, PredicateOperator.lessThanOrEqual);
        })
        .get();
    expect(
      manualDueRows,
      isNotEmpty,
      reason: 'manual due query should find entry',
    );

    final manualDueNoLocks = await adminConnections.context
        .query<$StemScheduleEntry>()
        .where((PredicateBuilder<$StemScheduleEntry> q) {
          q
            ..where('enabled', true, PredicateOperator.equals)
            ..where('nextRunAt', dueNow, PredicateOperator.lessThanOrEqual);
        })
        .orderBy('nextRunAt')
        .limit(5)
        .get();
    expect(manualDueNoLocks, isNotEmpty);

    final first = await store.due(dueNow, limit: 5);
    expect(first, hasLength(1));
    expect(first.single.id, entry.id);

    final second = await store.due(DateTime.now().toUtc(), limit: 5);
    expect(second, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    final third = await store.due(DateTime.now().toUtc(), limit: 5);
    expect(third, hasLength(1));
    expect(third.single.id, entry.id);
  });

  test('upsert updates entry and releases lock', () async {
    final now = DateTime.now().toUtc();
    final entry = ScheduleEntry(
      id: 'sched-2',
      taskName: 'task.update',
      queue: 'default',
      spec: CronScheduleSpec(expression: '* * * * *'),
      nextRunAt: now.subtract(const Duration(seconds: 1)),
    );

    await store.upsert(entry);
    final first = await store.due(DateTime.now().toUtc());
    expect(first, hasLength(1));

    final updated = first.single.copyWith(
      nextRunAt: now.add(const Duration(minutes: 5)),
      meta: const {'updated': true},
    );
    await store.upsert(updated);

    final second = await store.due(DateTime.now().toUtc());
    expect(second, isEmpty);

    final futureDue = await store.due(
      DateTime.now().toUtc().add(const Duration(minutes: 6)),
    );
    expect(futureDue, hasLength(1));
    expect(futureDue.single.meta['updated'], isTrue);
  });

  test('remove deletes schedule entry', () async {
    final now = DateTime.now().toUtc();
    final entry = ScheduleEntry(
      id: 'sched-3',
      taskName: 'task.remove',
      queue: 'default',
      spec: CronScheduleSpec(expression: '* * * * *'),
      nextRunAt: now.subtract(const Duration(seconds: 1)),
    );

    await store.upsert(entry);
    expect(
      (await store.due(DateTime.now().toUtc())).map((e) => e.id),
      contains(entry.id),
    );

    await store.remove(entry.id);
    final remaining = await store.due(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );
    expect(remaining, isEmpty);
  });
}
