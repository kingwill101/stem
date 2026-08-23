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
  deliveries; long-running tasks should rely on automatic renewal or explicitly
  extend their leases.
- **Postgres** uses polling with `locked_until` leases; tasks become visible
  again after the lease expires.

Worker lease renewal is isolated from the task loop. A failed automatic renewal
is contained, recorded as the `stem.lease.renewal_failed` metric, and logged with
the task, queue, and broker receipt; a shorter retry cadence gives transient
broker failures another chance before expiry. If the lease is ultimately lost,
the broker may redeliver the task. Stem persists the terminal result before
acknowledging, so a redelivery can observe terminal state instead of executing
the handler a second time.

The same lease remains active through terminal result persistence,
group/chord bookkeeping, retry or dead-letter publication, linked-task
dispatch, and acknowledgement. A slow backend or broker round trip during
that final handling window therefore gets the same renewal protection as the
handler itself.

Lease protection starts as soon as the delivery enters the worker, so slow
consume middleware, signature validation, backend lookups, and rate-limit
decisions are covered before handler execution begins.

If the same envelope is redelivered while its first delivery is still active
in the same worker, the duplicate is acknowledged without invoking the
handler again. This is a worker-local guard; recovery after a process crash
still follows Stem's at-least-once delivery model and requires idempotent
external side effects.

Hard shutdown requeues active deliveries, including deliveries already held in
the broker prefetch window. A replacement worker can therefore drain the full
batch; applications should still expect at-least-once execution for any
handler that was already running when the process stopped.

When two different workers complete the same task concurrently, built-in
result backends use `AtomicTerminalResultBackend` to arbitrate the terminal
state. Only the worker that wins that atomic write performs terminal group,
chord, linked-task, signal, and unique-lock side effects. This prevents a late
success or failure record from replacing the result that already won. Custom
result backends remain compatible, but must implement that optional capability
if they need the same cross-process first-writer-wins guarantee.

The worker suite also exercises the failure path where lease renewal fails
while a handler is still running. After the visibility timeout, a replacement
worker receives the redelivery and may finish first; the original handler's
late completion is then ignored by terminal arbitration. This is still
at-least-once execution: external side effects must be idempotent, and a
successful handler is not proof that its broker acknowledgement was durable.

Renewal is scheduled from roughly half of the remaining lease. The configured
minimum interval is used for ordinary leases, but it does not delay renewal of
short leases past their deadline. If the lease duration is shorter than the
default one-second floor, Stem uses the shorter safe interval instead.

## Workflow lease notes

- Workflow runs are lease-based. Workers must renew leases while executing, and
  other workers can take over after the lease expires.
- SQLite integration coverage reopens the durable workflow store after a
  worker/runtime restart and resumes a persisted checkpoint without re-running
  the completed step. The same checkpoint/replay contract applies to the
  other durable workflow stores, subject to their adapter guarantees.
- Keep `runLeaseDuration` **>=** broker visibility timeout to prevent
  redelivered workflow tasks from being dropped before takeover is possible.
- Keep `leaseExtension` renewals ahead of both the workflow lease expiry and the
  broker visibility timeout.

## Poison-pill handling

- Payload-decoding failures are terminal: Stem acknowledges the delivery,
  records a failed result, and dead-letters it with reason `invalid-payload`.
  They do not consume the task's normal handler retry budget because retrying
  the same malformed bytes cannot repair the message.
- If a task fails repeatedly for the same reason, treat it as a poison pill.
- Move it to the DLQ and add guardrails or validation to prevent repeats.
- Record the failure pattern for future detection.

## Scheduler reliability

- Run multiple Beat instances only when backed by a shared lock store.
- Beat revalidates lock ownership immediately before publishing; a lost lease
  records a failed dispatch instead of publishing after another scheduler may
  have acquired the entry.
- Fenced lock stores attach `stem-lock-fencing-token` to scheduled envelopes.
  Downstream state stores that support fencing should reject writes carrying a
  token older than the last accepted token. The token prevents stale owners
  from overwriting state after a lease expires; it does not make external
  side effects exactly once.
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

Use heartbeats and progress updates to make long-running tasks observable.
Automatic worker lease renewal protects normal executions; call
`context.extendLease(...)` when a task needs an explicit additional lease.

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
