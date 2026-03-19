---
title: Errors, Retries, and Idempotency
---

Durable orchestration only works if replayed code is safe. In Stem, that means
understanding where retries happen and where you need idempotent boundaries.

## Flow retries

Flow steps are durable stage boundaries. A suspended flow step is re-entered by
the runtime after resume, and the step body must tolerate replay.

Use:

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
