# Scheduler Parity Features

Stem's scheduler now mirrors Celery Beat's core capabilities while remaining
backwards compatible with existing interval/cron schedules. This document
summarises the new behaviour, configuration options, and rollout guidance.

## Schedule Specifications

Schedule entries can now express richer time semantics via `ScheduleSpec`:

- **Interval** – `IntervalScheduleSpec` supports millisecond resolution plus
  optional `startAt` / `endAt`. Legacy strings (`every:5m`) continue to work.
- **Cron** – `CronScheduleSpec` accepts the classic five-field expression and
  optional second-field/description metadata. Per-entry `timezone` is honoured
  when the schedule store is created with a timezone resolver.
- **Solar** – `SolarScheduleSpec` triggers at sunrise, sunset, or solar noon
  given latitude/longitude and an optional offset.
- **Clocked** – `ClockedScheduleSpec` executes once at a specific timestamp
  (`runOnce`) or retriggers when advanced.
- **Calendar** – `CalendarScheduleSpec` offers Celery-style filters (months,
  weekdays, monthdays, hours, minutes) which are compiled to cron during
  evaluation.

`ScheduleEntry` now includes:

- `kwargs` stored alongside `args` in the schedule definition.
- Execution metadata (`totalRunCount`, `lastSuccessAt`, `lastErrorAt`, `drift`).
- Optional `expireAt` to disable entries after a deadline.

## Store Enhancements

- **Postgres**: `stem_schedule_entries` gained JSON `spec`, `kwargs`, history
  metrics, and an associated `stem_schedule_run_history` table capturing
  execution outcomes. Upserts accept the new fields and mark entries disabled
  when `runOnce` or `expireAt` boundaries are reached.
- **Redis**: Entries are stored as hashes with JSON-encoded specs, arguments,
  and metadata. A per-schedule stream (`stem:schedule:<id>:history`) records the
  latest executions, trimmed to 1,000 events.
- **In-memory**: Mirrors the expanded metadata surface, supporting `expireAt`
  and run-once semantics for local testing.

All stores now accept a custom `ScheduleCalculator` so you can plug in timezone
resolvers (`ScheduleTimezoneResolver`) and deterministic random implementations.

## Scheduler Engine (Beat)

- Beat records the scheduled timestamp, actual execution, jitter applied, drift,
  and success/failure metadata via `ScheduleStore.markExecuted`.
- Broadcast envelopes include `kwargs` inside the metadata payload so workers
  can interpret keyword arguments consistently.
- Run-once clocked schedules are automatically disabled after dispatch.

## CLI & Tooling

- `stem schedule list` renders friendly descriptions via `_describeSpec`, e.g.
  `every 30s`, `sunrise @40.71/-74.01`, or `once 2025-01-01T09:00:00Z`.
- `stem schedule enable|disable <id>` toggles entries without restarting Beat.
- `stem schedule apply` and file repositories persist the full JSON form of the
  schedule spec, preserving kwargs and metadata.
- `stem schedule dry-run --spec` accepts the same JSON structure (or legacy
  `every:` strings) and honours per-entry timezones when previewing occurrences.

## Observability

- Postgres and Redis stores maintain recent execution history that can be used
  by future observability surfaces (`stem observe schedules`, dashboards).
- Drift metrics are tracked (`executedAt - scheduledFor`) so you can alert on
  scheduler lag when clusters experience load or pauses.

## Rollout Guidance

1. Apply the Postgres schema changes (they are backwards-compatible).
2. Deploy the new code across Beat instances and workers.
3. If you depend on per-entry time zones or solar schedules, install
   `timezone/data/latest.dart` and initialise the data prior to constructing the
   schedule store.
4. Update automation and documentation to use the JSON schedule format rather
   than string-based specs.
