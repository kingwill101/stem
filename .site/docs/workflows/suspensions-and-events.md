---
title: Suspensions and Events
---

Suspension is where workflows differ from normal queue consumers. A workflow
can stop executing, persist its state, and resume later on the same worker or a
different worker. Suspension is durable state, not a blocked Dart `Future`.

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
When you inspect watcher entries directly, use `watcher.dataJson(...)` or
`watcher.dataAs(codec: ...)` when the full watcher metadata maps to one DTO.
If only the nested watcher payload is a DTO, use `watcher.payloadJson(...)` or
`watcher.payloadAs(codec: ...)` instead of manual raw-map casts.

Typical flow:

1. a step calls `awaitEvent('orders.payment.confirmed')`
2. the runtime persists the suspension and watcher before the run is treated
   as waiting
3. another process calls `WorkflowRuntime.emit(...)` /
   `WorkflowRuntime.emitValue(...)` (or an app/service wrapper around it) with
   a payload
4. the store resolves matching watchers and the runtime enqueues continuations;
   the event is not buffered for a future watcher
5. the resumed run replays from its durable checkpoint and exposes the payload
   through `waitForEvent(...)`, `event.wait(ctx)`, or the lower-level
   `takeResumeData()` / `takeResumeValue<T>(codec: ...)`

An emit therefore only wakes watchers that exist when it resolves the topic.
Emit after the watcher has been registered, and do not use a topic as a
run-addressed mailbox. A single emit may resolve all matching waiting runs.

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
an explicit `__stemPayloadVersion`, `WorkflowEventRef<T>.versionedMap(...)`
when the payload needs a custom map encoder plus stored schema version, and
keep `event.emit(emitter, dto)` as the happy path.
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

## Replay, retries, and null values

After a crash or lease loss, completed checkpoints are replayed from the store;
they are not executed as new business work. The continuation can still be
delivered more than once, so external effects need idempotency. A stale worker
cannot commit over a newer owner: execution leases and fencing checks protect
the persisted transition.

The expression-style `waitForEventValue<T>` and `takeResumeValue<T>` helpers use
`null` as the “no resume payload yet” sentinel. That makes them unsuitable for
distinguishing a delivered `null` event from the first invocation. For nullable
values, use an explicit non-null envelope/map (as `HostedWorkflowContext` does)
or a lower-level path whose control metadata distinguishes resume from payload.
Codecs preserve scalar values and `null` when the destination permits them, but
event watcher transport itself remains map-shaped.

## Group operations

Because due runs and event watchers are persisted, you can:

- resume batches of runs waiting on one topic
- inspect all suspended runs even with no active worker
- rebuild dashboard views after process restarts
