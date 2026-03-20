---
title: Suspensions and Events
---

Suspension is where workflows differ from normal queue consumers. A workflow
can stop executing, persist its state, and resume later on the same worker or a
different worker.

## Sleep

`sleep(duration)` records a wake-up time in the workflow store. The runtime
periodically scans due runs and re-enqueues the internal workflow task when the
sleep expires.

For the common "sleep once, continue on resume" case, prefer the higher-level
helper:

```dart
await ctx.sleepFor(duration: const Duration(milliseconds: 200));
```

## Await external events

`awaitEvent(topic, deadline: ...)` records a durable watcher. External code can
resume those runs through the runtime API by emitting a payload for the topic.

Typical flow:

1. a step calls `awaitEvent('orders.payment.confirmed')`
2. the run is marked suspended in the store
3. another process calls `WorkflowRuntime.emit(...)` /
   `WorkflowRuntime.emitValue(...)` (or an app/service wrapper around it) with
   a payload
4. the runtime resumes the run and exposes the payload through
   `waitForEvent(...)`, `event.wait(ctx)`, or the lower-level
   `takeResumeData()` / `takeResumeValue<T>(codec: ...)`

For the common "wait for one event and continue" case, prefer:

```dart
final payload = await ctx.waitForEvent<Map<String, Object?>>(
  topic: 'orders.payment.confirmed',
);
```

## Emit resume events

Use `WorkflowRuntime.emit(...)` / `WorkflowRuntime.emitValue(...)` (or the app
wrapper `workflowApp.emitValue(...)`) instead of hand-editing store state:

```dart
await workflowApp.emitValue(
  'orders.payment.confirmed',
  const PaymentConfirmed(paymentId: 'pay_42', approvedBy: 'gateway'),
  codec: paymentConfirmedCodec,
);
```

Typed event payloads still serialize to the existing `Map<String, Object?>`
wire format. `emitValue(...)` is a DTO/codec convenience layer, not a new
transport shape.

When the topic and codec travel together in your codebase, prefer
`WorkflowEventRef<T>.json(...)` for normal DTO payloads and keep
`event.emit(emitter, dto)` as the happy path. `event.call(value).emit(...)`
remains available as the lower-level prebuilt-call variant.
Pair that with `await event.wait(ctx)`.

## Inspect waiting runs

The workflow store can tell you which runs are waiting on a topic:

- `runsWaitingOn(topic)`
- `listRuns(...)`

That is the foundation for dashboards, operational tooling, and bulk
inspection.

## Group operations

Because due runs and event watchers are persisted, you can:

- resume batches of runs waiting on one topic
- inspect all suspended runs even with no active worker
- rebuild dashboard views after process restarts
