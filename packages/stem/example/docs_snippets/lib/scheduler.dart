// Beat scheduler examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

// #region beat-load
Future<void> loadSchedules() async {
  final store = await RedisScheduleStore.connect('redis://localhost:6379/2');
  final beat = Beat(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    store: store,
    lockStore: await RedisLockStore.connect('redis://localhost:6379/3'),
  );

  await applyScheduleFile(store, 'config/schedules.yaml');
  await beat.start();
}
// #endregion beat-load

// #region beat-dev
Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(DemoTask());
  final broker = InMemoryBroker();
  final store = InMemoryScheduleStore();
  final lockStore = InMemoryLockStore();

  final beat = Beat(
    broker: broker,
    store: store,
    lockStore: lockStore,
  );

  await store.upsert(
    ScheduleEntry(
      id: 'demo-once',
      taskName: 'demo.run',
      queue: 'default',
      spec: ClockedScheduleSpec(
        runAt: DateTime.now().add(const Duration(seconds: 5)),
      ),
    ),
  );

  await beat.start();
  await Future<void>.delayed(const Duration(seconds: 6));
  await beat.stop();
}

class DemoTask extends TaskHandler<void> {
  @override
  String get name => 'demo.run';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print('Running scheduled job at ${DateTime.now()}');
  }
}
// #endregion beat-dev

// #region beat-redis
Future<void> startRedisBeat() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final store = await RedisScheduleStore.connect('$brokerUrl/2');
  final beat = Beat(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    store: store,
    lockStore: await RedisLockStore.connect('$brokerUrl/3'),
  );

  await applyScheduleFile(store, 'config/schedules.yaml');
  await beat.start();
}

class EmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
// #endregion beat-redis

// #region beat-postgres
Future<void> startPostgresBeat() async {
  final scheduleUrl =
      Platform.environment['STEM_SCHEDULE_STORE_URL'] ??
      'postgres://postgres:postgres@localhost:5432/stem';
  final store = await PostgresScheduleStore.connect(scheduleUrl);
  final beat = Beat(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    store: store,
    lockStore: await PostgresLockStore.connect(scheduleUrl),
  );

  await applyScheduleFile(store, 'config/schedules.yaml');
  await beat.start();
}

class ReportTask extends TaskHandler<void> {
  @override
  String get name => 'reports.generate';

  @override
  TaskOptions get options => const TaskOptions(queue: 'reports');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
// #endregion beat-postgres

// #region beat-interval-spec
Future<void> addIntervalSchedule(ScheduleStore store) async {
  await store.upsert(
    ScheduleEntry(
      id: 'interval-demo',
      taskName: 'demo.interval',
      queue: 'default',
      spec: IntervalScheduleSpec(
        every: const Duration(minutes: 10),
      ),
      jitter: const Duration(minutes: 1),
    ),
  );
}
// #endregion beat-interval-spec

// #region beat-cron-spec
Future<void> addCronSchedule(ScheduleStore store) async {
  await store.upsert(
    ScheduleEntry(
      id: 'cron-demo',
      taskName: 'demo.cron',
      queue: 'default',
      spec: CronScheduleSpec(expression: '0 12 * * MON'),
    ),
  );
}
// #endregion beat-cron-spec

// #region beat-solar-spec
Future<void> addSolarSchedule(ScheduleStore store) async {
  await store.upsert(
    ScheduleEntry(
      id: 'solar-demo',
      taskName: 'demo.solar',
      queue: 'default',
      spec: SolarScheduleSpec(
        event: 'sunrise',
        latitude: 51.5072,
        longitude: -0.1276,
        offset: const Duration(minutes: 30),
      ),
    ),
  );
}
// #endregion beat-solar-spec

// #region beat-clocked-spec
Future<void> addClockedSchedule(ScheduleStore store) async {
  final runAt = DateTime.now().add(const Duration(hours: 6));
  await store.upsert(
    ScheduleEntry(
      id: 'clocked-demo',
      taskName: 'demo.clocked',
      queue: 'default',
      spec: ClockedScheduleSpec(runAt: runAt),
    ),
  );
}
// #endregion beat-clocked-spec

// #region beat-specs
Future<void> addScheduleSpecs(ScheduleStore store) async {
  await addIntervalSchedule(store);
  await addCronSchedule(store);
  await addSolarSchedule(store);
  await addClockedSchedule(store);
}
// #endregion beat-specs

// #region beat-signals
void registerBeatSignals() {
  StemSignals.scheduleEntryDue.connect((payload, _) {
    print('[due] ${payload.entry.id} @ ${payload.tickAt}');
  });

  StemSignals.scheduleEntryDispatched.connect((payload, _) {
    print('[dispatched] drift=${payload.drift.inMilliseconds}ms');
  });

  StemSignals.scheduleEntryFailed.connect((payload, _) {
    print('[failed] ${payload.entry.id}: ${payload.error}');
  });
}
// #endregion beat-signals

Future<void> applyScheduleFile(ScheduleStore store, String path) async {
  // Use `stem schedule apply --file <path>` to upsert YAML-defined schedules.
}

// #region beat-due
Future<void> listDueEntries(ScheduleStore store) async {
  final dueEntries = await store.due(DateTime.now());
  for (final entry in dueEntries) {
    print('Upcoming: ${entry.id} at ${entry.nextRunAt}');
  }
}

// #endregion beat-due
