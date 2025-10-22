## 1. Discovery & Design
- [x] 1.1 Audit current scheduler capabilities (interval/cron, storage) and document gaps vs Celery Beat.
- [x] 1.2 Finalize data model changes for schedule store (solar, clocked, metadata) in design.md.

## 2. Schedule Store Enhancements
- [x] 2.1 Extend Postgres schedule tables with new fields (timezone, solar args, run_once, enabled, last_run_at history).
- [x] 2.2 Implement alternative store adapters (Redis hash/JSON, in-memory) with parity features.

## 3. Scheduler Engine
- [x] 3.1 Add support for solar and clocked schedules plus per-entry timezone handling.
- [x] 3.2 Implement drift correction and jitter configuration to avoid stampedes.
- [x] 3.3 Track run history (last run, next run, total runs, error state) for observability.

## 4. Runtime CRUD & Reload
- [x] 4.1 Build CLI/API commands to list, add, update, enable/disable, and delete schedules at runtime.
- [ ] 4.2 Ensure scheduler reloads updates without restart and handles conflict resolution in clustered mode.

## 5. Observability & Docs
- [ ] 5.1 Expose schedule metrics/logging (due counts, missed runs) and surface via CLI.
- [x] 5.2 Document new schedule types, CLI usage, and migration guide.

## 6. Validation
- [x] 6.1 `dart format`, `dart analyze`, `dart test`, plus integration tests covering new schedule types and CRUD operations.
- [x] 6.2 `openspec validate add-scheduler-parity --strict` before review.
