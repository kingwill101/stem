---
title: Workflow Troubleshooting
---

## The workflow never starts

**Check:** confirm `await workflowApp.start()` runs, the workflow is
registered, a worker consumes the orchestration queue, and the durable
workflow store is reachable.

**Remedy:** correct bootstrap/registration and start a worker with the same
store and namespace. This is task delivery, not a journal retry.

## A regular task inside a workflow never runs

**Check:** orchestration and regular tasks may use different queues. Confirm a
worker consumes the target queue and has the task registered.

**Remedy:** start the appropriate task worker or correct routing. Do not
increase workflow `maxAttempts` to compensate for an unsubscribed queue.

## A step keeps failing

**Check:** distinguish queue redelivery/task retry from `WorkflowRetryPolicy`.
`maxAttempts` includes the first logical step attempt and survives restart;
queue deliveries do not reset it.

**Remedy:** fix the step or dependency and choose a bounded journal policy. If
it exhausts, handle `WorkflowStepRetryExhausted`; do not replay the queue
indefinitely.

## Compensation keeps failing

**Check:** compensation has its own journal namespace and attempt budget.
Inspect `WorkflowCompensationRetryExhausted` and its persisted failure.

**Remedy:** repair or reconcile external state, then use the supported
workflow operation. Compensation is not the forward-step budget.

## Resume events do nothing

**Check:** the topic passed to `WorkflowRuntime.emit`/`emitValue` must match
`awaitEvent`. Confirm the run is waiting, the store is reachable, and the
payload is a string-keyed JSON-like value.

**Remedy:** emit the matching value once the run is waiting, or cancel it
deliberately. Event handling is not exactly once; consumers must be idempotent.

## Restart or redelivery repeats work

**Check:** inspect the persisted checkpoint/journal and lease/visibility
timeouts. A completed checkpoint should recover from durable state; an
abandoned claim may be attempted again.

**Remedy:** use a durable workflow store, size leases for the operation, and
make effects idempotent. Mobile apps have no background-lifetime guarantee:
suspension or termination can interrupt a run. Run durable workers on a server
when completion is required.

## Serialization or store errors

**Check:** values crossing workflow boundaries must be encodable by the active
codec and supported by the adapter. Verify migrations, store URL, namespace,
and definition compatibility.

**Remedy:** encode domain objects as JSON-like maps/lists, migrate using the
adapter instructions, and deploy compatible workflow definitions.
