## Why
- Celery Beat offers rich scheduler features (multiple schedule types, database-backed entries, runtime CRUD, clock drift correction, time zone awareness) that Stem’s scheduler lacks, making migrations difficult.
- Stem’s scheduler supports basic cron/interval entries but misses solar schedules, dynamic updates, persistent enable/disable toggles, and run-from-now semantics.
- Operators need CLI/API control to manage schedules without redeploying, plus observability into due times and last run status.

## What Changes
- Expand Stem’s scheduler to support additional schedule types (solar, clocked, fixed intervals), per-entry time zones, and drift compensation.
- Introduce a pluggable schedule store (Postgres, Redis, in-memory) with runtime CRUD operations, history tracking, and enable/disable toggles.
- Add CLI/API endpoints for managing periodic tasks and querying scheduler state, including exporting schedules.
- Implement persistence for last-run status, jitter configuration, and calendar-based filters.

## Impact
- Requires schema extensions and migration tooling for schedule storage.
- Scheduler runtime must handle dynamic config reloads safely and coordinate across distributed instances.
- CLI/docs need updates; existing schedules must migrate automatically to new schema.
