---
title: Stem Signals
sidebar_label: Signals
sidebar_position: 4
slug: /core-concepts/signals
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Stem now exposes Celery-style lifecycle signals so instrumentation can react to
publish, worker, scheduler, and control-plane events without modifying the
runtime. All payloads live in `package:stem/src/signals/payloads.dart` and map
directly to Stem's task and worker data structures.

## Signal Catalog

| Category | Stem Signal | Payload Highlights | Celery Equivalent |
| --- | --- | --- | --- |
| Publish | `beforeTaskPublish`, `afterTaskPublish` | `Envelope`, attempt metadata, task id | `before_task_publish`, `after_task_publish` |
| Worker lifecycle | `workerInit`, `workerReady`, `workerStopping`, `workerShutdown`, `workerHeartbeat`, `workerChildInit`, `workerChildShutdown` | `WorkerInfo`, optional reason/timestamps | `worker_init`, `worker_ready`, `worker_shutting_down`, `worker_shutdown`, `heartbeat_sent`, `worker_process_init/shutdown` |
| Task lifecycle | `taskReceived`, `taskPrerun`, `taskPostrun`, `taskRetry`, `taskSucceeded`, `taskFailed`, `taskRevoked` | `Envelope`, `WorkerInfo`, attempt, result/error context | `task_received`, `task_prerun`, `task_postrun`, `task_retry`, `task_success`, `task_failure`, `task_revoked` |
| Scheduler | `scheduleEntryDue`, `scheduleEntryDispatched`, `scheduleEntryFailed` | `ScheduleEntry`, tick timestamp, drift, error stack | `beat_scheduler_ready`, `beat_schedule` |
| Control plane | `controlCommandReceived`, `controlCommandCompleted` | `ControlCommandMessage`, reply status, payload/error maps | `control_command_sent`, `control_command_received` |

## Ordering & Semantics

- `beforeTaskPublish` fires immediately before broker IO; `afterTaskPublish`
  runs once persistence succeeds.
- `taskReceived` is emitted after middleware but before the task context is
  created.
- `taskPrerun` precedes handler execution; `taskPostrun` runs after completion,
  regardless of outcome. Success and failure signals fire before `taskPostrun`.
- Worker lifecycle events follow `workerInit` → `workerReady` → optional
  `workerStopping` → `workerShutdown`. Heartbeats (`workerHeartbeat`) include
  namespace and queue metadata.
- Scheduler signals fire `scheduleEntryDue` → dispatch →
  `scheduleEntryDispatched` or `scheduleEntryFailed`.
- Handler exceptions are caught, logged, and surfaced via
  `StemSignals.signalDispatchFailed` while the dispatcher continues processing
  remaining listeners unless `SignalContext.cancel()` is invoked.

Handlers execute sequentially (respecting registration priority). `async`
callbacks are awaited so ordering remains deterministic.

## Configuration

Use `StemSignals.configure` or supply environment variables consumed by
`ObservabilityConfig.fromEnvironment`:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-configure

```

Environment knobs:

- `STEM_SIGNALS_ENABLED=false` disables all signals.
- `STEM_SIGNALS_DISABLED=worker-heartbeat,task-prerun` disables selected ones.

Workers automatically apply the configuration passed through
`ObservabilityConfig`, enabling cluster-wide rollouts without code changes.

## Listening for signals

<Tabs>
<TabItem value="publish" label="Publish">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-publish-listeners

```

</TabItem>
<TabItem value="task" label="Task lifecycle">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-task-listeners

```

</TabItem>
<TabItem value="worker" label="Worker lifecycle">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-worker-listeners

```

</TabItem>
<TabItem value="scheduler" label="Scheduler">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-scheduler-listeners

```

</TabItem>
<TabItem value="control" label="Control plane">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-control-listeners

```

</TabItem>
</Tabs>

## Adapters & Middleware

- `StemSignalEmitter` builds payloads and emits signals; it powers Stem itself
  and is available for custom middleware or broker integrations.
- `SignalMiddleware.coordinator()` forwards enqueue middleware to publish
  signals, while `SignalMiddleware.worker()` emits `taskReceived`,
  `taskPrerun`, and `taskFailed` from existing worker middleware chains. Success
  and postrun events remain wired through the runtime so result payloads stay
  accurate.

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-middleware-producer

```

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-middleware-worker

```

## Example (Docker Compose)

`examples/signals_demo` spins up a Redis broker, producer, and worker. Running:

```bash
docker compose up --build
```

streams every signal as structured JSON, showcasing retries, failures, worker
heartbeats, scheduler drift, and control commands.

### Retry-Focused Walkthrough

For a minimal reproduction of retry cadence, try `examples/retry_task`. The
worker connects to Redis with `blockTime=100ms`, `claimInterval=200ms`, and
`defaultVisibilityTimeout=2s`, and uses
`ExponentialJitterRetryStrategy(base: 200ms, max: 1s)` so each retry happens in
under a second. The producer enqueues a single task with `maxRetries=2`, and the
console prints every `task_retry`, `task_failed`, and `task_postrun` signal.
Experiment with the strategy or Redis timings to see how they shape retry
frequency.

## Celery Comparison

| Celery | Stem | Notes |
| --- | --- | --- |
| `task_prerun` / `task_postrun` | `taskPrerun` / `taskPostrun` | Payload includes the Stem `TaskContext` for heartbeats and lease helpers. |
| `worker_ready` | `workerReady` | Provides queue/broadcast subscriptions for visibility. |
| `worker_process_init/shutdown` | `workerChildInit` / `workerChildShutdown` | Mirrors isolate pool spawn/recycle notifications. |
| `before_task_publish` | `beforeTaskPublish` | Fires before middleware or broker calls. |
| `beat_schedule` | `scheduleEntryDispatched` | Carries scheduled vs executed timestamps plus drift duration. |

Signals tied to Celery-specific pools remain out of scope; raise a proposal if
additional parity is required.

## Performance & Testing

Dispatch short-circuits when disabled, keeping the hot path cheap. Unit tests
exercise dispatcher priority, handler error handling, worker/scheduler events,
retry semantics, and the `SignalMiddleware` adapter, ensuring migrations from
Celery receive the expected hook coverage.
