---
title: Reliability Guide
sidebar_label: Reliability
sidebar_position: 10
slug: /getting-started/reliability
---

This guide summarizes reliability practices for task systems using Stem.

## Recovery workflow

1. Identify the failing task or queue.
2. Inspect recent errors and DLQ entries.
3. Fix the root cause before replaying.
4. Replay only the affected tasks.

## Broker fetch notes

- **Redis Streams** uses consumer groups plus `XAUTOCLAIM` to reclaim idle
  deliveries; long-running tasks should emit heartbeats or extend leases.
- **Postgres** uses polling with `locked_until` leases; tasks become visible
  again after the lease expires.

## Poison-pill handling

- If a task fails repeatedly for the same reason, treat it as a poison pill.
- Move it to the DLQ and add guardrails or validation to prevent repeats.
- Record the failure pattern for future detection.

## Scheduler reliability

- Run multiple Beat instances only when backed by a shared lock store.
- Monitor schedule drift and failures to detect store latency.
- Re-apply schedules after deploys to ensure definitions stay current.

## Retries and backoff

- Use bounded retries with jittered backoff to avoid thundering herds.
- Separate transient failures from permanent failures.
- For permanent errors, fail fast and alert.

## Observability signals

- Track retry rates and DLQ volume as reliability signals.
- Monitor queue backlog and worker heartbeats to detect stalls.
- Tie task IDs to business logs for fast root-cause analysis.
- Use `StemSignals.taskRetry` / `taskFailed` to drive notifications when error
  rates spike.

## Operational checks

```bash
stem health --broker "$STEM_BROKER_URL" --backend "$STEM_RESULT_BACKEND_URL"
stem observe queues
stem observe workers
stem dlq list --queue <queue>
```

## Next steps

- [Troubleshooting](./troubleshooting.md)
- [Observability & Ops](./observability-and-ops.md)
- [Worker Control CLI](../workers/worker-control.md)
