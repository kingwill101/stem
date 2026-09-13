---
title: Errors, Retries, and Idempotency
---

Durable orchestration only works if replayed code is safe. In Stem, that means
understanding where retries happen and where you need idempotent boundaries.

## Flow retries

Flow steps are durable stage boundaries. A suspended flow step is re-entered by
the runtime after resume, and the step body must tolerate replay.

Use:

- `await ctx.sleepFor(duration: ...)` for the expression-style sleep path
- `await ctx.waitForEvent(topic: ...)` for the expression-style event path
- `sleepUntilResumed(...)` for simple sleep/replay loops
- `waitForEventValue<T>(...)` for one-event suspension points
- `takeResumeData()` to branch on fresh resume payloads
- `idempotencyKey(...)` when a step talks to an external side-effecting system
- persisted previous results instead of in-memory state

## Script checkpoint retries

In script workflows, completed checkpoints are replay-safe boundaries. The
runtime restores completed checkpoint results and continues through the
remaining `script.step(...)` calls.

The code between durable checkpoints should still avoid hidden side effects.

## Task retries inside workflows

If a workflow enqueues normal Stem tasks, those tasks still use the normal
`TaskOptions` retry policy. The workflow and the task are separate retry
surfaces.

## Hosted journal retries

The function-first host also supports a durable logical budget for a named
action. It is separate from task delivery retries:

```dart
await context.step(
  'charge',
  () => paymentClient.charge(orderId),
  retry: const WorkflowRetryPolicy(maxAttempts: 3),
);
```

`maxAttempts` includes the first attempt and abandoned claims after a crash.
The journal persists attempts and retry times, so transport redelivery does
not reset the budget. An exhausted action throws
`WorkflowStepRetryExhausted`; it does not start another task-level retry.

## Result-aware compensation

Hosted workflows can register a typed compensation and attach it to a
checkpoint. Compensation is not a transaction or rollback of an external
system, and broader saga policy tooling remains deferred:

```dart
final undo = HostedCompensation<String>(
  name: 'undo-reservation',
  run: (context, reservationId) =>
      reservations.release(reservationId, idempotencyKey: context.idempotencyKey),
  retryPolicy: const WorkflowRetryPolicy(maxAttempts: 3),
);
```

Register it in `HostedWorkflow.compensations` and pass `compensation: undo` to
the relevant `context.step`. Make both the action and cleanup idempotent.

## Acknowledgement uncertainty

Task delivery is at least once. Stem records a successful result before the
final broker acknowledgement. If that acknowledgement is lost, the broker
may redeliver the same envelope; the worker recognizes the durable terminal
result and acknowledges the duplicate without invoking the handler again.
External side effects must still be idempotent because a process can fail
before its result is recorded.

## Cancellation policies

Use `WorkflowCancellationPolicy` when you need to cap:

- overall run duration
- maximum suspension duration

That turns unbounded waiting into an explicit terminal state.

## Rules of thumb

- treat external writes as idempotent operations
- never rely on process-local memory for workflow progress
- keep side effects behind task handlers or clearly named checkpoints
- encode enough metadata to safely detect duplicate execution attempts
