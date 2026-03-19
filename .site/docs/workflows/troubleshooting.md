---
title: Troubleshooting
---

These are the workflow-specific issues you are most likely to hit first.

## The workflow never starts

Check:

- the app was started with `await workflowApp.start()`
- a worker is subscribed to the workflow orchestration queue
- the workflow name is registered in `flows:` or `scripts:`

## A normal task inside the workflow never runs

The workflow worker may only be subscribed to the `workflow` queue. If the
workflow enqueues regular tasks, make sure some worker also consumes the target
task queue such as `default`.

## Resume events do nothing

Check:

- the topic passed to `WorkflowRuntime.emit(...)` / `emitValue(...)` or
  `workflowApp.emitValue(...)` matches the one passed to `awaitEvent(...)`
- the run is still waiting on that topic
- the payload encodes to a `Map<String, Object?>`

## Serialization failures

Do not pass arbitrary Dart objects across workflow or task boundaries. Encode
domain objects as `Map<String, Object?>` or `List<Object?>` first.

## Logs only show `stem.workflow.run`

Upgrade to a build that includes the newer workflow log context. The logs
should include workflow name, run id, channel, and checkpoint metadata in
addition to the internal task name.

## Leases or redelivery behave strangely

Check the relationship between:

- broker visibility timeout
- workflow run lease duration
- lease renewal cadence

If the broker redelivers before the workflow lease model expects, another
worker can observe a task before the prior lease is considered stale.
