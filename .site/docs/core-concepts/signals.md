---
title: Stem Signals
sidebar_label: Signals
sidebar_position: 4
slug: /core-concepts/signals
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Stem exposes lifecycle signals so instrumentation can react to publish, worker,
scheduler, workflow, and control-plane events without modifying runtime code.

All signal payloads implement `StemEvent` and dispatch through
`Signal<T extends StemEvent>`, giving every handler a shared event shape:

- `eventName`
- `occurredAt`
- `attributes`

## Signal Catalog

| Category | Stem Signal | Payload Highlights | Celery Equivalent |
| --- | --- | --- | --- |
| Publish | `beforeTaskPublish`, `afterTaskPublish` | `Envelope`, attempt metadata, task id | `before_task_publish`, `after_task_publish` |
| Worker lifecycle | `workerInit`, `workerReady`, `workerStopping`, `workerShutdown`, `workerHeartbeat`, `workerChildInit`, `workerChildShutdown` | `WorkerInfo`, optional reason/timestamps | `worker_init`, `worker_ready`, `worker_shutting_down`, `worker_shutdown`, `heartbeat_sent`, `worker_process_init/shutdown` |
| Task lifecycle | `taskReceived`, `taskPrerun`, `taskPostrun`, `taskRetry`, `taskSucceeded`, `taskFailed`, `taskRevoked` | `Envelope`, `WorkerInfo`, attempt, result/error context | `task_received`, `task_prerun`, `task_postrun`, `task_retry`, `task_success`, `task_failure`, `task_revoked` |
| Workflow lifecycle | `workflowRunStarted`, `workflowRunSuspended`, `workflowRunResumed`, `workflowRunCompleted`, `workflowRunFailed`, `workflowRunCancelled` | run id, workflow name, status, optional step metadata | n/a |
| Scheduler | `scheduleEntryDue`, `scheduleEntryDispatched`, `scheduleEntryFailed` | `ScheduleEntry`, tick timestamp, drift, error stack | `beat_scheduler_ready`, `beat_schedule` |
| Control plane | `controlCommandReceived`, `controlCommandCompleted` | `ControlCommandMessage`, reply status, payload/error maps | `control_command_sent`, `control_command_received` |

## Ordering & Dispatch Semantics

- `beforeTaskPublish` fires immediately before broker IO; `afterTaskPublish`
  runs once persistence succeeds.
- `taskReceived` is emitted when a worker claims/dequeues a task.
- `taskPrerun` fires immediately before handler invocation.
- Execution ordering is `taskReceived` -> `taskPrerun` -> handler -> `taskPostrun`.
- Worker lifecycle follows `workerInit` -> `workerReady` -> optional
  `workerStopping` -> `workerShutdown`.
- Scheduler signals emit due -> dispatched/failed.
- Dispatch is sequential and priority-aware; `async` callbacks are awaited.
- Listener errors are routed to `StemSignals.configure(onError: ...)` and do not
  crash the worker loop.
- `SignalContext.cancel()` stops lower-priority listeners for the current emit.

## Configuration

Use `StemSignals.configure` or supply environment variables consumed by
`ObservabilityConfig.fromEnvironment`:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-configure

```

Environment knobs:

- `STEM_SIGNALS_ENABLED=false` disables all signals.
- `STEM_SIGNALS_DISABLED=worker-heartbeat,task-prerun` disables selected ones.

## Listening for Signals

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
<TabItem value="worker-scoped" label="Worker-scoped filters">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-worker-scoped

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
<TabItem value="stem-event" label="StemEvent view">

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-stem-event

```

</TabItem>
</Tabs>

Worker-scoped filtering is available on these convenience helpers:

- `onWorkerInit`, `onWorkerReady`, `onWorkerStopping`, `onWorkerShutdown`
- `onWorkerHeartbeat`, `onWorkerChildInit`, `onWorkerChildShutdown`
- `onTaskReceived`, `onTaskPrerun`, `onTaskPostrun`, `onTaskSuccess`,
  `onTaskFailure`, `onTaskRetry`, `onTaskRevoked`
- `onControlCommandReceived`, `onControlCommandCompleted`

## Custom Queue Events

Signals cover runtime lifecycle hooks. For application-domain events (BullMQ
`QueueEvents` style), use [`QueueEventsProducer` and `QueueEvents`](./queue-events.md).

## Adapters & Middleware

- `StemSignalEmitter` builds payloads and emits signals; Stem runtime uses this
  same emitter internally.
- `SignalMiddleware.coordinator()` forwards enqueue middleware to publish
  signals.
- `SignalMiddleware.worker()` emits receive/prerun/failure hooks from existing
  worker middleware chains.

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-middleware-producer

```

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-middleware-worker

```

## Celery Comparison

| Celery | Stem | Notes |
| --- | --- | --- |
| `task_prerun` / `task_postrun` | `taskPrerun` / `taskPostrun` | Payload includes `TaskContext` and worker metadata. |
| `worker_ready` | `workerReady` | Worker-scoped filters available via `onWorkerReady(workerId: ...)`. |
| `worker_process_init/shutdown` | `workerChildInit` / `workerChildShutdown` | Mirrors isolate pool spawn/recycle notifications. |
| `before_task_publish` | `beforeTaskPublish` | Fires before broker writes. |
| `beat_schedule` | `scheduleEntryDispatched` | Carries scheduled vs executed timestamps plus drift duration. |

Signals tied to Celery-specific pools remain out of scope.
