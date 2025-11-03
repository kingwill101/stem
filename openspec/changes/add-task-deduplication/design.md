# Design: Unique Task Coordination

## Current State
`TaskOptions.unique` and `uniqueFor` are surfaced in the public API, yet
`Stem.enqueue` never checks them. As a result, the flag conveys a false sense of
safety. Lock infrastructure already exists for scheduler coordination
(`LockStore`, `Lock`), but nothing in the enqueue/worker pipeline uses it.

## Requirements Recap
- A unique task must only be queued/running once within the configured window.
- Duplicate enqueue attempts should return the existing task id to avoid
  creating multiple result entries.
- Uniqueness should naturally expire after `uniqueFor`, or when the original
  task reaches a terminal state.
- The approach must work across multiple producer processes.

## Proposed Architecture
Introduce a `UniqueTaskCoordinator` responsible for:
1. Deriving a deterministic dedupe key from the task name plus arguments,
   headers, and optional override metadata (e.g. `meta['uniqueKey']` if
   supplied).
2. Attempting to acquire a lock in the configured `LockStore` with TTL equal to
   `uniqueFor` (fallback to `visibilityTimeout` or 5 minutes).
3. Storing the winning task id inside the lock payload (owner) and persisting a
   marker in the result backend meta for observability.
4. Releasing the lock when the worker marks the task as succeeded, failed, or
   cancelled.

Producer path:
- `Stem.enqueue` checks options; if unique, it calls coordinator.acquire.
- On success, the coordinator returns an object containing the task id and a
  release hook; enqueue proceeds normally.
- On conflict, the coordinator returns the existing task id and a reason so the
  caller can skip publishing and emit a duplicate signal/metric.

Worker path:
- After moving a task to a terminal state, call coordinator.release to clean up.
- If the worker crashes before release, the lock naturally expires via TTL.

## Alternatives Considered
- **Result-backend check without locks:** Query the backend for existing jobs in
  non-terminal states. This would require new indices/queries on every backend
  and does not prevent race conditions between concurrent producers.
- **Broker-level dedupe:** Some brokers (e.g. Redis) support ZSET-based dedupe,
  but making every adapter implement bespoke logic increases complexity and
  still requires a global key. Centralising in the core keeps behaviour
  consistent across brokers.

## Open Questions
- Should callers be able to supply their own dedupe key explicitly? Proposal:
  accept `meta['uniqueKey']` if present; otherwise hash arguments.
- How should we surface duplicate skips to the caller? Options include signals,
  metrics, and optional return type (e.g. `EnqueueResult`). For now, return the
  existing id and record metadata; additional API surfacing can follow.
