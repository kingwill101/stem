---
title: Scheduler Parity
sidebar_label: Parity & Features
sidebar_position: 1
slug: /scheduler/parity
---

Stem's scheduler now matches Celery Beat's core capabilities while preserving
backwards compatibility with existing interval/cron entries.

## Schedule Specifications

- **Interval** — `IntervalScheduleSpec` supports millisecond resolution and
  optional `startAt` / `endAt`. Existing `every:5m` strings are still accepted.
- **Cron** — `CronScheduleSpec` evaluates classic five-field expressions and
  honours optional seconds/description metadata. Per-entry `timezone` values are
  respected when the schedule store is configured with a
  `ScheduleTimezoneResolver`.
- **Solar** — `SolarScheduleSpec` triggers at sunrise, sunset, or solar noon for
  a latitude/longitude with optional offsets.
- **Clocked** — `ClockedScheduleSpec` runs at a specific timestamp; `runOnce`
  disables the entry after dispatch.
- **Calendar** — `CalendarScheduleSpec` mimics Celery's calendar filters
  (months, weekdays, monthdays, hours, minutes) and compiles internally to
  cron.

`ScheduleEntry` now captures kwargs, run counters, drift, and optional expiry to
give operators tighter visibility and control.

## Storage Improvements

- **Postgres** adds JSON `spec`/`kwargs`, execution counters, and a
  `schedule_run_history` table. Upserts manage run-once/expiry disabling
  out-of-the-box.
- **Redis** stores JSON specs and metadata in hashes, and appends execution
  events to a per-schedule stream (`stem:schedule:<id>:history`) trimmed to the
  latest 1,000 entries.
- **In-memory** mirrors the new metadata, making parity features testable
  without external services.

All stores accept a `ScheduleCalculator` so you can supply timezone resolvers or
custom randomness if required.

## Scheduler Engine

Beat records scheduled time, actual execution, jitter, drift, and
success/failure during `markExecuted`. Run-once entries and `expireAt` deadlines
are automatically disabled. Broadcast envelopes include `kwargs` (merged into
metadata) so workers can interpret keyword arguments consistently.

## CLI & Tooling

- `stem schedule list` renders friendly descriptions such as `every 30s`,
  `sunrise @40.71/-74.01`, and `once 2025-01-01T09:00:00Z`.
- `stem schedule enable|disable <id>` toggles entries without restarting Beat.
- `stem schedule apply` persists the full JSON representation so kwargs and
  metadata survive round-trips. When pointed at a store it retries optimistic
  lock conflicts (up to five attempts) and merges existing execution metadata so
  operators keep last-run, drift, and counters intact.
- `stem schedule enable|disable <id>` uses the same retry loop to make toggles
  resilient while clustered beats race to update schedule versions.
- `stem schedule dry-run --spec` accepts the same JSON blob (or legacy strings)
  and honours entry time zones when previewing upcoming runs.
- `stem observe schedules` prints a summary of due/overdue counts (including
  live gauge snapshots) plus a table with total runs, drift, next run, and last
  error for each entry, regardless of whether the backend is a file repo or a
  remote store.

## Observability

- Postgres/Redis stores maintain lightweight run history that can feed into
  future dashboards and CLI inspection.
- Drift metrics (`executedAt - scheduledFor`) reveal scheduler lag so you can
  alert on paused or overloaded Beat instances.

## Rollout

1. Apply the Postgres schema migrations (they are backwards compatible).
2. Deploy the updated scheduler/worker binaries.
3. Initialise timezone data (via `timezone/data/latest.dart`) if you intend to
   use per-entry time zones or solar schedules.
4. Update automation/docs to prefer JSON schedule specs over raw strings.
