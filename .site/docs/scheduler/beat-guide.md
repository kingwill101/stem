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

Apply schedule files to the schedule store before calling `beat.start()`:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-load

```

To build schedules imperatively, call `store.upsert` with the spec classes
(`IntervalScheduleSpec`, `CronScheduleSpec`, `SolarScheduleSpec`, `ClockedScheduleSpec`).

## Start Beat

<Tabs>
<TabItem value="in-memory" label="In-memory (Local)">

```dart title="bin/beat_dev.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-dev

```

</TabItem>
<TabItem value="redis" label="Redis Schedule Store">

```dart title="bin/beat_redis.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-redis

```

</TabItem>
<TabItem value="postgres" label="Postgres Schedule Store">

```dart title="bin/beat_postgres.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-postgres

```

</TabItem>
</Tabs>

### CLI alternative

Prefer configuration over code? Use the CLI with the same schedule file:

```bash
stem schedule apply \
  --file config/schedules.yaml \
  --store "$STEM_SCHEDULE_STORE_URL"

stem beat start \
  --store "$STEM_SCHEDULE_STORE_URL" \
  --broker "$STEM_BROKER_URL" \
  --registry lib/main.dart
```

## Programmatic spec helpers

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-specs

```

| Spec          | Description |
| ------------- | ----------- |
| `Interval`    | Millisecond-resolution interval with optional jitter, `startAt`, `endAt`. |
| `Cron`        | Classic 5/6-field cron with optional timezone per entry. |
| `Solar`       | Sunrise, sunset, or solar noon with lat/long and optional offsets. |
| `Clocked`     | One-shot timestamp; set `runOnce` to prevent rescheduling. |

## Timezone handling

- Schedule entries accept an optional IANA timezone identifier.
- If your schedule store uses the default calculator, schedules evaluate in UTC.
- To honor per-entry timezones, construct the schedule store with a
  `ScheduleCalculator` configured with a timezone data provider.
- You must load timezone data in your process (for example,
  `timezone/data/latest.dart`) before using a timezone-aware calculator.

## Observe Beat activity

Stem emits scheduler signals that mirror Celery Beat hooks:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-signals

```

You can also query the schedule store directly:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-due

```

## Tips & tricks

- Use `lockStore` (Redis or Postgres) when running Beat in HA mode so only one
  instance triggers jobs at a time.
- Call `Beat.stop()` on shutdown to flush outstanding timers and release locks.
- Combine Beat with `stem worker start --bundle` to ship the same registry to
  both components.
- Store schedules in source control and re-apply them with
  `stem schedule apply` after deployments.

Next, hook Beat into your deployment automation and monitor the scheduler
signals alongside worker metrics.
