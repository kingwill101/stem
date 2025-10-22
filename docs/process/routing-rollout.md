# Routing Parity Rollout

Multi-queue workers, priority dispatch, and broadcast fan-out introduce new
schema and configuration surface. This guide outlines the recommended rollout
order for operators.

## Postgres migrations

Run the new schema changes before deploying workers that subscribe to
broadcasts or publish priorities. The migration contains the following DDL:

```sql
ALTER TABLE stem_jobs
  ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS stem_jobs_priority_idx
  ON stem_jobs (queue, priority DESC, created_at);

CREATE TABLE IF NOT EXISTS stem_broadcast_messages (
  id TEXT PRIMARY KEY,
  channel TEXT NOT NULL,
  envelope JSONB NOT NULL,
  delivery TEXT NOT NULL DEFAULT 'at-least-once',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS stem_broadcast_ack (
  message_id TEXT NOT NULL REFERENCES stem_broadcast_messages(id) ON DELETE CASCADE,
  worker_id TEXT NOT NULL,
  acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, worker_id)
);
```

Suggested sequence:

1. Apply the migration (no downtime required). The new column defaults to 0
   and existing workers continue to function.
2. Deploy brokers/workers with the new code path.
3. After verifying traffic, drop any legacy fallback indexes if they exist.

## Redis notes

Broadcast fan-out relies on Redis Streams consumer groups (`XGROUP` /
`XREADGROUP`). Ensure your Redis nodes are running Redis 5.0 or newer. No
additional schema changes are required.

## Feature gating

Workers remain single-queue until configured. Use the new environment
variables/flags to opt-in:

- `--queue` / `--broadcast` on `stem worker multi` populate
  `STEM_WORKER_QUEUES` and `STEM_WORKER_BROADCASTS`.
- Library consumers can call `buildWorkerSubscription` with the loaded
  `StemConfig` and `RoutingRegistry` to construct a `RoutingSubscription`.

Roll out by enabling subscriptions on a subset of workers first, monitoring the
updated `stem.worker.*` metrics and `stem worker stats` output, then finishing
the rollout across remaining nodes.
