## Overview
Stem’s scheduler currently supports interval and cron schedules stored in Postgres/Redis, with limited toggling. To match Celery Beat we need:

1. **Expanded schedule types**: Solar schedules (sunrise/sunset), clocked (run once at specific datetime), calendar-like filters, per-entry timezone handling.
2. **Robust storage**: Pluggable schedule stores with persistent metadata (enabled, args, last run, total run count, error information) and configuration for jitter/drift.
3. **Runtime management**: CLI/API for CRUD, enabling/disabling entries, forcing immediate runs, exporting/importing schedules.
4. **Observability**: Metrics, logs, and CLI outputs capturing next due times, missed runs, drift corrections.

## Data Model
Update schedule entry schema:
```
ScheduleEntry {
  id: String,
  taskName: String,
  schedule: ScheduleSpec,
  args: Map,
  kwargs: Map,
  enabled: bool,
  lastRunAt: DateTime?,
  nextRunAt: DateTime?,
  totalRunCount: int,
  lastError: String?,
  jitterMs: int?,
  timezone: String?,
  expireAt: DateTime?,
}

ScheduleSpec = IntervalSpec | CronSpec | SolarSpec | ClockedSpec
```
- **IntervalSpec**: `every`, `period`, `start`, `end`.
- **CronSpec**: existing fields plus `day_of_week`, `day_of_month`, `month_of_year`, `solar_offset` future support.
- **SolarSpec**: `event` (sunrise/sunset/noon), `latitude`, `longitude`.
- **ClockedSpec**: `runAt`, `runOnce` flag, optional `timezone`.

Stores must support partial updates (enabled toggles), history writes, and concurrency-safe locking to avoid duplicate runs.

## Scheduler Engine
- Extend scheduler to evaluate new specs. For solar, integrate a solar position library (Dart port or minimal algorithm). Cache calculations per day to avoid heavy computation.
- Implement `DriftCorrector` that compares actual vs expected run time; logs warning if drift exceeds threshold and adjusts `nextRunAt`.
- Allow per-entry jitter (random or deterministic) to spread executions.

## Runtime CRUD
- Provide `SchedulerService` that watches store changes. UI/CLI commands (`stem schedule add`, `update`, `enable`, `disable`, `run-now`, `list`, `delete`).
- Support live reload: scheduler listens to store change stream or uses polling with etag/version to pick up modifications without restart.
- For Postgres, use `LISTEN/NOTIFY` to push updates; for Redis, use pub/sub.

## Observability
- Metrics: number of enabled schedules, due tasks, drift corrections, run durations.
- Logging: entry-level logs when executed, skipped, disabled, or error.
- CLI `stem observe schedules` showing next run, last run, jitter, status.

## Migration
- Provide migration script to add new columns to Postgres tables and backfill defaults.
- For Redis/in-memory stores, version the schema and perform compatibility shim.
- Modeled to be backwards-compatible: if new fields absent, default to existing behaviour.
