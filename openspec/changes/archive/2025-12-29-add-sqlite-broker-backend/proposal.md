## Why
- Mobile and desktop deployments need an embedded queue/result store without managing a Redis or Postgres server.
- Prototyping the SQLite driver on desktop lets us harden the semantics before adapting it to background isolates on mobile.
- The dashboard should visualize queue health for the SQLite prototype so we can gauge contention, retries, and DLQ volume.

## What Changes
- Add a SQLite-backed broker implementation that satisfies Stem’s broker contract (enqueue, consume, ack/nack, lease management, DLQ).
- Add a SQLite-backed result backend that mirrors the Postgres feature set (task status TTLs, groups, worker heartbeats, watchers).
- Extend the dashboard service so it can read queue and heartbeat metrics directly from the SQLite store for local prototyping.
- Document operational constraints (WAL mode, sweeper cadence, crash recovery expectations) so future Turso usage can reuse the design.

## Impact
- Enables offline/embedded workloads to enqueue and execute tasks without external infra.
- Provides observability into the embedded queue to tune contention and retry behavior before mobile rollout.
- Establishes a portable schema and data-access layer that can target Turso/libSQL when cross-device sync becomes desirable.
