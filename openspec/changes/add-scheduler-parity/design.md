## Current State & Gaps

Stem’s Beat implementation retrieves due entries via `ScheduleStore.due` and
supports two spec formats:

- **Interval** (`every:5m` style) evaluated in `ScheduleCalculator._parseEvery`.
- **Cron** expressions with five fields (`minute hour day month weekday`).

Entries are persisted with:

- Core fields: `id`, `taskName`, `queue`, `spec`, `args`, `enabled`.
- Optional metadata: `jitter`, `lastRunAt`, `lastJitter`, `lastError`, `timezone`.
- Stores: Postgres (`stem_schedule` table) and Redis (sorted set) plus an
  in-memory adapter used by tests.

Observed limitations compared to Celery Beat / change goals:

| Capability | Current Stem behaviour | Gap |
|------------|------------------------|-----|
| Schedule types | Interval + Cron only | No solar events, clocked (one-shot), calendar filters |
| Time zones | `ScheduleEntry.timezone` stored but unused during evaluation | Need per-entry TZ execution |
| Drift handling | Next run derived from last run; no compensation for system pauses | Should track expected vs actual and reschedule |
| Jitter | Global optional jitter; no deterministic jitter or jitter reporting beyond last execution | Need per-entry jitter config persisted & surfaced |
| Enable/disable | Boolean `enabled` flag honoured; no persisted history | Need toggles with audit trail |
| Run history | `lastRunAt`, `lastError`, `lastJitter` only | Need total run count, previous error history, miss detection |
| CRUD tooling | `stem schedule` limited to upsert/list; no disable/run-now/inspect commands | CLI/API parity required |
| Store parity | Postgres & Redis support minimal fields | Need schema extensions, history table, enable/disable updates, versioning |
| Multi-instance coordination | Lock store optional; no change notifications | Need LISTEN/NOTIFY / pubsub for live reload |

## Overview Target
Stem’s scheduler must evolve to match Celery Beat parity:

1. **Expanded schedule types**: Solar schedules (sunrise/sunset), clocked (run once at specific datetime), calendar-like filters, per-entry timezone handling.
2. **Robust storage**: Pluggable schedule stores with persistent metadata (enabled, args, last run, total run count, error information) and configuration for jitter/drift.
3. **Runtime management**: CLI/API for CRUD, enabling/disabling entries, forcing immediate runs, exporting/importing schedules.
4. **Observability**: Metrics, logs, and CLI outputs capturing next due times, missed runs, drift corrections.

## Data Model
Update schedule entry schema:
```
ScheduleEntry {
  id: String,                   // stable key
  taskName: String,             // registered task
  queue: String,                // routing target
  schedule: ScheduleSpec,       // polymorphic spec payload
  args: Map<String, Object?>,
  kwargs: Map<String, Object?>, // optional, parity with Celery
  enabled: bool,
  jitterMs: int?,               // max jitter per execution
  timezone: String?,            // IANA zone for cron/clocked
  lastRunAt: DateTime?,
  nextRunAt: DateTime?,         // cached to avoid recompute
  totalRunCount: int,
  lastSuccessAt: DateTime?,
  lastErrorAt: DateTime?,
  lastError: String?,
  driftMs: int?,                // delta between expected vs actual run
  expireAt: DateTime?,          // optional auto-expire
  createdAt: DateTime,
  updatedAt: DateTime,
}

ScheduleSpec =
    IntervalSpec
  | CronSpec
  | SolarSpec
  | ClockedSpec
  | CalendarSpec

IntervalSpec {
  every: Duration,
  startAt: DateTime?,
  endAt: DateTime?,
}

CronSpec {
  expression: String,           // existing 5-field cron
  secondField: String?,         // optional 6th field for parity
  dayOfWeek: String?,           // friendly aliases (mon, tue,…)
}

SolarSpec {
  event: 'sunrise'|'sunset'|'noon',
  latitude: double,
  longitude: double,
  offset: Duration?,            // +/- shift
}

ClockedSpec {
  runAt: DateTime,
  runOnce: bool,
}

CalendarSpec {
  months: List<int>?,
  weekdays: List<int>?,
  monthdays: List<int>?,
  hours: List<int>?,
  minutes: List<int>?,
}
```

- **History tracking**: Append-only `schedule_runs` table with fields
  `(id, schedule_id, executed_at, success, duration_ms, error_text)` for
  operator visibility. Stores may cap history entries at configurable length.
- **State versioning**: `updatedAt` + `version` column for optimistic locking
  so CLI edits fail fast if the record changes underneath.

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
