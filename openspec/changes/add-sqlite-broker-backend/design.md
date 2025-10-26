## Overview
The change introduces SQLite-backed implementations for the broker and result backend so Stem can run fully embedded on desktop (and later mobile). The same schema must remain portable to libSQL/Turso so we can switch to a hosted endpoint without rewriting the data-access layer. The design favors short transactions, WAL mode, and explicit sweepers to compensate for SQLite’s coarse locking.

## Components
1. **SqliteConnections helper**
   - Opens a file-backed database, enables `journal_mode=WAL` and `synchronous=NORMAL`.
   - Exposes `Future<T> runInTransaction<T>(Future<T> Function(CommonDatabase txn))` for re-usable transactional code shared by the broker and backend.

2. **SqliteBroker**
   - Tables: `stem_queue_jobs`, `stem_dead_letters`, optional `stem_status_events` for dashboard updates.
   - Enqueue uses `INSERT OR REPLACE` semantics to support idempotent pushes.
   - Dequeue uses `BEGIN IMMEDIATE` + `UPDATE ... WHERE locked_by IS NULL` to mark a job claimed. Falls back to exponential backoff when none available.
   - Crash recovery handled by sweeper that resets locks with expired `locked_until`.
   - DLQ writes into `stem_dead_letters` with JSON payloads and TTL cleanup.

3. **SqliteResultBackend**
   - Tables mirror Postgres backend fields but store JSON as TEXT and timestamps as ISO8601.
   - Supports `store`, `retrieve`, `purge`, group aggregation, and worker heartbeats.
   - Periodic cleanup removes expired task results and heartbeats.

4. **Dashboard Data Source**
   - New `SqliteDashboardService` that points at the SQLite database file.
   - Queries aggregate queue depth (`COUNT(*)` on pending vs locked rows), dead-letter count, and returns worker heartbeat rows.
   - A lightweight polling loop (every 2s) pushes updates to the Turbo stream hub.

## Concurrency Considerations
- All queue mutations happen inside `BEGIN IMMEDIATE` transactions (<5ms target) to minimize lock time.
- Background sweeper resets `locked_by/locked_until` for stale jobs and performs TTL cleanup for results & DLQ.
- Configurable polling interval for consumers (`pollInterval`) to balance responsiveness with lock pressure.

## Turso Compatibility
- Avoids SQLite-specific pragmas beyond WAL/synchronous that Turso already supports.
- Uses standard SQL (no triggers or virtual tables) so queries execute unchanged on libSQL.
- Connection factory wraps libSQL client when the URI starts with `libsql://`, reusing the same DAO layer.

## Failure Modes & Mitigations
- **App crash during transaction**: rely on atomic commit/rollback; jobs remain pending or locked with an expiration.
- **Device sleep/offline**: sweeper requeues expired locks when the app resumes.
- **Database bloat**: cleanup tasks remove TTL’d rows; provide CLI hook to vacuum during maintenance.
