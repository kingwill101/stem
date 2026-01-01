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

## Poison-pill handling

- If a task fails repeatedly for the same reason, treat it as a poison pill.
- Move it to the DLQ and add guardrails or validation to prevent repeats.
- Record the failure pattern for future detection.

## Retries and backoff

- Use bounded retries with jittered backoff to avoid thundering herds.
- Separate transient failures from permanent failures.
- For permanent errors, fail fast and alert.

## Observability signals

- Track retry rates and DLQ volume as reliability signals.
- Monitor queue backlog and worker heartbeats to detect stalls.
- Tie task IDs to business logs for fast root-cause analysis.

## Operational checks

```bash
stem health --broker "$STEM_BROKER_URL" --backend "$STEM_RESULT_BACKEND_URL"
stem dlq list --broker "$STEM_BROKER_URL"
stem observe tasks list --broker "$STEM_BROKER_URL"
```

## Next steps

- [Troubleshooting](./troubleshooting.md)
- [Observability & Ops](./observability-and-ops.md)
- [Worker Control CLI](../workers/worker-control.md)
