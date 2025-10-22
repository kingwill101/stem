---
title: Beat Scheduler Guide
sidebar_label: Beat Scheduler
sidebar_position: 2
slug: /scheduler/beat
---

Stem Beat enqueues periodic tasks so you can keep background jobs on schedule.
This guide shows how to define schedules, load them, run Beat alongside your
workers, and monitor results.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Define schedules

Beat accepts YAML, JSON, or programmatic entries. YAML keeps schedules under
version control and mirrors the CLI format:

```yaml title="config/schedules.yaml"
cleanup-temp-files:
  task: maintenance.cleanup
  spec: every:5m
  queue: maintenance
  args:
    path: /tmp
  options:
    maxRetries: 2

midnight-report:
  task: reports.generate
  spec:
    cron: '0 0 * * *'
    timezone: America/New_York
  queue: reports
  kwargs:
    report: daily-summary

solar-check:
  task: solar.notify
  spec:
    solar: sunset
    latitude: 40.7128
    longitude: -74.0060
    offset: -15m

one-off-reconcile:
  task: billing.reconcile
  spec:
    clocked: 2025-02-01T00:00:00Z
  queue: finance
  options:
    runOnce: true
```

## Load schedules

Call `startFromYamlFile` (or its JSON/programmatic counterparts) before
`beat.start()`:

```dart
final beat = Beat(
  broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
  registry: SimpleTaskRegistry()..register(ReportTask()),
  store: await RedisScheduleStore.connect('redis://localhost:6379/2'),
  lockStore: await RedisLockStore.connect('redis://localhost:6379/3'),
);

await beat.startFromYamlFile('config/schedules.yaml');
await beat.start();
```

To build schedules imperatively, call `store.upsert` with the spec classes
(`IntervalScheduleSpec`, `CronScheduleSpec`, `SolarScheduleSpec`, `ClockedScheduleSpec`).

## Start Beat

<Tabs>
<TabItem value="in-memory" label="In-memory (Local)">

```dart title="bin/beat_dev.dart"
import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(DemoTask());
  final broker = InMemoryBroker();
  final store = InMemoryScheduleStore();
  final lockStore = InMemoryLockStore();

  final beat = Beat(
    broker: broker,
    registry: registry,
    store: store,
    lockStore: lockStore,
  );

  await store.upsert(
    ScheduleEntry(
      id: 'demo-once',
      taskName: 'demo.run',
      spec: ClockedScheduleSpec(DateTime.now().add(const Duration(seconds: 5))),
    ),
  );

  await beat.start();
}

class DemoTask implements TaskHandler<void> {
  @override
  String get name => 'demo.run';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print('Running scheduled job at ${DateTime.now()}');
  }
}
```

</TabItem>
<TabItem value="redis" label="Redis Schedule Store">

```dart title="bin/beat_redis.dart"
import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final registry = SimpleTaskRegistry()..register(EmailTask());

  final beat = Beat(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    registry: registry,
    store: await RedisScheduleStore.connect('$brokerUrl/2'),
    lockStore: await RedisLockStore.connect('$brokerUrl/3'),
  );

  await beat.startFromYamlFile('config/schedules.yaml');
  await beat.start();
}
```

</TabItem>
<TabItem value="postgres" label="Postgres Schedule Store">

```dart title="bin/beat_postgres.dart"
import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main() async {
  final scheduleUrl = Platform.environment['STEM_SCHEDULE_STORE_URL'] ??
      'postgres://postgres:postgres@localhost:5432/stem';
  final registry = SimpleTaskRegistry()..register(ReportTask());

  final beat = Beat(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    registry: registry,
    store: await PostgresScheduleStore.connect(scheduleUrl),
    lockStore: await PostgresLockStore.connect(scheduleUrl),
  );

  await beat.startFromYamlFile('config/schedules.yaml');
  await beat.start();
}
```

</TabItem>
</Tabs>

### CLI alternative

Prefer configuration over code? Use the CLI with the same schedule file:

```bash
stem scheduler start   --broker "$STEM_BROKER_URL"   --schedule config/schedules.yaml   --registry lib/main.dart
```

## Programmatic spec helpers

```dart
await store.upsert(
  ScheduleEntry(
    id: 'interval-demo',
    taskName: 'demo.interval',
    spec: IntervalScheduleSpec(every: const Duration(minutes: 10), jitter: const Duration(minutes: 1)),
  ),
);

await store.upsert(
  ScheduleEntry(
    id: 'cron-demo',
    taskName: 'demo.cron',
    spec: CronScheduleSpec.fromString('0 12 * * MON', timezone: 'UTC'),
  ),
);

await store.upsert(
  ScheduleEntry(
    id: 'solar-demo',
    taskName: 'demo.solar',
    spec: SolarScheduleSpec.sunrise(
      latitude: 51.5072,
      longitude: -0.1276,
      offset: const Duration(minutes: 30),
    ),
  ),
);
```

| Spec          | Description |
| ------------- | ----------- |
| `Interval`    | Millisecond-resolution interval with optional jitter, `startAt`, `endAt`. |
| `Cron`        | Classic 5/6-field cron with optional timezone per entry. |
| `Solar`       | Sunrise, sunset, or solar noon with lat/long and optional offsets. |
| `Clocked`     | One-shot timestamp; set `runOnce` to prevent rescheduling. |

## Observe Beat activity

Stem emits scheduler signals that mirror Celery Beat hooks:

```dart
StemSignals.onScheduleEntryDue((payload, _) {
  print('[due] ${payload.entry.id} @ ${payload.tickAt}');
});

StemSignals.onScheduleEntryDispatched((payload, _) {
  print('[dispatched] drift=${payload.drift.inMilliseconds}ms');
});

StemSignals.onScheduleEntryFailed((payload, _) {
  print('[failed] ${payload.entry.id}: ${payload.error}');
});
```

You can also query the schedule store directly:

```dart
final dueEntries = await store.due(DateTime.now());
for (final entry in dueEntries) {
  print('Upcoming: ${entry.id} at ${entry.nextRunAt}');
}
```

## Tips & tricks

- Use `lockStore` (Redis or Postgres) when running Beat in HA mode so only one
  instance triggers jobs at a time.
- Call `Beat.stop()` on shutdown to flush outstanding timers and release locks.
- Combine Beat with `stem worker start --bundle` to ship the same registry to
  both components.
- Store schedules in source control and reload via `beat.startFromYamlFile`
  after deployments.

Next, hook Beat into your deployment automation and monitor the scheduler
signals alongside worker metrics.
