---
title: Scheduler
slug: /scheduler
sidebar_position: 0
---

Stem Beat coordinates periodic work across your cluster. Explore the scheduler
capabilities, storage backends, and operational tooling.

## What Beat does

Beat reads schedule definitions from a schedule store, evaluates when each entry
is due, and enqueues the corresponding task. Use it for cron-style jobs,
interval tasks, solar events, or one-off clocked runs.

## Schedule spec types

Stem ships concrete spec types you can store or generate:

- **Interval** (`IntervalScheduleSpec`) — run every N seconds/minutes/hours.
- **Cron** (`CronScheduleSpec`) — standard cron expressions.
- **Solar** (`SolarScheduleSpec`) — sunrise/sunset-based schedules.
- **Clocked** (`ClockedScheduleSpec`) — single run at a specific time.

## Beat in production

Beat is a separate process from workers. It only enqueues tasks; workers still
execute them. That separation means you can scale Beat (and its schedule store)
independently from worker fleets.

## HA and lock stores

To run Beat in high availability mode, multiple Beat instances can share the
same schedule store and a lock store. The lock store ensures only one scheduler
emits a given schedule entry at a time. Redis and Postgres stores support this
pattern out of the box.

## Schedule stores

Beat persists schedule entries so restarts do not lose state. For production,
use a shared schedule store (Redis/Postgres) and a lock store to coordinate HA
instances. The CLI schedule commands use `STEM_SCHEDULE_STORE_URL` when set;
otherwise they operate on local schedule files.

## CLI entrypoints

Common scheduler CLI commands:

- `stem schedule apply` — load schedule entries from JSON/YAML into the store.
- `stem schedule list` — inspect entries in the store.
- `stem schedule dry-run` — preview due times before rollout.
- `stem observe schedules` — inspect schedule drift and dispatch status.

Beat itself runs as a Dart process; see the Beat guide for entrypoints.

- **[Beat Scheduler Guide](./beat-guide.md)** – Configure Beat, load schedules, and run it with in-memory, Redis, or Postgres stores.
- **Example:** `example/scheduler_observability` shows drift metrics, schedule signals, and CLI inspection.

Looking for locking and storage details? See the Postgres and Redis sections in
[Broker Overview](../brokers/overview.md).
