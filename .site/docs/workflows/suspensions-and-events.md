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
When you inspect watcher entries directly, use `watcher.payloadJson(...)` or
`watcher.payloadAs(codec: ...)` instead of manual raw-map casts.

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
final payload = await ctx.waitForEventJson<PaymentConfirmed>(
  topic: 'orders.payment.confirmed',
  decode: PaymentConfirmed.fromJson,
);
```

## Emit resume events

Use `WorkflowRuntime.emit(...)` / `WorkflowRuntime.emitJson(...)` /
`WorkflowRuntime.emitVersionedJson(...)` / `WorkflowRuntime.emitValue(...)`
(or the app wrappers `workflowApp.emitJson(...)` /
`workflowApp.emitVersionedJson(...)` / `workflowApp.emitValue(...)`) instead
of hand-editing store state:

```dart
await workflowApp.emitJson(
  'orders.payment.confirmed',
  const PaymentConfirmed(paymentId: 'pay_42', approvedBy: 'gateway'),
);
```

Typed event payloads still serialize to a string-keyed JSON-like map.
`emitJson(...)`, `emitVersionedJson(...)`, and `emitValue(...)` are
DTO/codec convenience layers, not a new transport shape.

When the topic and codec travel together in your codebase, prefer
`WorkflowEventRef<T>.json(...)` for normal DTO payloads,
`WorkflowEventRef<T>.versionedJson(...)` when the payload schema should carry
an explicit `__stemPayloadVersion`, and keep `event.emit(emitter, dto)` as the
happy path. `event.call(value).emit(...)` remains available as the lower-level
prebuilt-call variant.
Pair that with `await event.wait(ctx)`. If you are writing a flow and
deliberately want the lower-level `FlowStepControl` path, use
`event.awaitOn(step)` instead of dropping back to a raw topic string.
For low-level sleep/event directives that still need DTO metadata, use
`step.sleepJson(...)`, `step.sleepVersionedJson(...)`,
`step.awaitEventJson(...)`, `step.awaitEventVersionedJson(...)`, or
`FlowStepControl.awaitTopicJson(...)` instead of hand-built maps.

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
