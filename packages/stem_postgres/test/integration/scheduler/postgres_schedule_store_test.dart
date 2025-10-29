import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:stem/stem.dart';
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
  late PostgresClient adminClient;

  Future<void> clearTables() async {
    await adminClient.run((conn) async {
      await conn.execute('DELETE FROM public.${namespace}_schedule_locks');
      await conn.execute('DELETE FROM public.${namespace}_schedule_entries');
    });
  }

  setUp(() async {
    adminClient = PostgresClient(connectionString);
    store = await PostgresScheduleStore.connect(
      connectionString,
      namespace: namespace,
      lockTtl: const Duration(milliseconds: 300),
      applicationName: 'stem-postgres-schedule-test',
    );
    await clearTables();
  });

  tearDown(() async {
    await clearTables();
    await store.close();
    await adminClient.close();
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

    final rows = await adminClient.run((conn) async {
      return conn.execute(
        'SELECT id, next_run_at, enabled FROM public.${namespace}_schedule_entries',
      );
    });
    expect(rows, isNotEmpty, reason: 'entry should be persisted');
    final storedNextRun = rows.first[1] as DateTime;
    expect(
      storedNextRun.isBefore(
        DateTime.now().toUtc().add(const Duration(seconds: 1)),
      ),
      isTrue,
      reason: 'next_run_at should be in the past',
    );

    final dueNow = DateTime.now().toUtc();

    final manualDueRows = await adminClient.run((conn) async {
      return conn.execute(
        'SELECT id FROM public.${namespace}_schedule_entries WHERE enabled = true AND next_run_at <= NOW()',
      );
    });
    expect(
      manualDueRows,
      isNotEmpty,
      reason: 'manual due query should find entry',
    );

    final manualDueWithJoin = await adminClient.run((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT e.id
        FROM public.${namespace}_schedule_entries e
        LEFT JOIN public.${namespace}_schedule_locks l ON e.id = l.id
        WHERE e.enabled = true AND e.next_run_at <= @now AND l.id IS NULL
        ORDER BY e.next_run_at ASC
        LIMIT @limit
        '''),
        parameters: {'now': dueNow, 'limit': 5},
      );
    });
    expect(manualDueWithJoin, isNotEmpty);

    final lockCountBefore = await adminClient.run((conn) async {
      final result = await conn.execute(
        'SELECT COUNT(*) FROM public.${namespace}_schedule_locks',
      );
      return result.first.first as int;
    });
    expect(lockCountBefore, equals(0));

    final first = await store.due(dueNow, limit: 5);
    final lockCountAfter = await adminClient.run((conn) async {
      final result = await conn.execute(
        'SELECT COUNT(*) FROM public.${namespace}_schedule_locks',
      );
      return result.first.first as int;
    });
    expect(lockCountAfter, equals(1));
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
