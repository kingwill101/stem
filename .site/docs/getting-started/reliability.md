---
title: Reliability Guide
sidebar_label: Reliability
sidebar_position: 10
slug: /getting-started/reliability
---

This guide summarizes reliability practices for task systems using Stem.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

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

## Workflow lease notes

- Workflow runs are lease-based. Workers must renew leases while executing, and
  other workers can take over after the lease expires.
- Keep `runLeaseDuration` **>=** broker visibility timeout to prevent
  redelivered workflow tasks from being dropped before takeover is possible.
- Keep `leaseExtension` renewals ahead of both the workflow lease expiry and the
  broker visibility timeout.

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

<Tabs>
<TabItem value="worker-retry" label="Configure a jittered retry strategy">

```dart title="retry_task/bin/worker.dart" file=<rootDir>/../packages/stem/example/retry_task/bin/worker.dart#reliability-retry-worker

```

</TabItem>
<TabItem value="signals" label="Log retry signals and outcomes">

```dart title="retry_task/lib/shared.dart" file=<rootDir>/../packages/stem/example/retry_task/lib/shared.dart#reliability-retry-signals

```

</TabItem>
<TabItem value="task" label="Create a task that exercises retries">

```dart title="retry_task/lib/shared.dart" file=<rootDir>/../packages/stem/example/retry_task/lib/shared.dart#reliability-retry-entrypoint

```

</TabItem>
</Tabs>

## Heartbeats and progress

Use heartbeats and progress updates to prevent long-running tasks from being
reclaimed prematurely.

<Tabs>
<TabItem value="heartbeat" label="Configure worker heartbeat intervals">

```dart title="progress_heartbeat/bin/worker.dart" file=<rootDir>/../packages/stem/example/progress_heartbeat/bin/worker.dart#reliability-heartbeat-worker

```

</TabItem>
<TabItem value="progress" label="Emit progress and heartbeats inside a task">

```dart title="progress_heartbeat/lib/shared.dart" file=<rootDir>/../packages/stem/example/progress_heartbeat/lib/shared.dart#reliability-progress-task

```

</TabItem>
<TabItem value="events" label="Stream worker events for observability">

```dart title="progress_heartbeat/lib/shared.dart" file=<rootDir>/../packages/stem/example/progress_heartbeat/lib/shared.dart#reliability-worker-event-logging

```

</TabItem>
</Tabs>

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
