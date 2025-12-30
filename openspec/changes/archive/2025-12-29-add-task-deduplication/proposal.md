# Proposal: Enforce Unique Task Enqueueing

## Background
Consumers can flag a task with `TaskOptions.unique` (and optionally supply
`uniqueFor`) to indicate that only one logical job should be queued or executing
at a time. The Stem API exposes those options today, but the core enqueue path
ignores them; duplicate requests are published normally, leading to unexpected
double work, duplicate notifications, or inconsistent downstream state. Teams
have started toggling the flag expecting protection, so we need to wire in real
deduplication semantics before the option rolls into production apps.

## Problem
- `Stem.enqueue` publishes every request even when `TaskOptions.unique` is set.
- Workers do not coordinate around a dedupe key, so duplicate payloads execute
  in parallel while the first job is still queued or running.
- `uniqueFor` has no effect, so callers cannot bound how long uniqueness should
  hold once the task has completed.

## Goals
- Enforce single-queue semantics for tasks that opt into uniqueness.
- Provide predictable behaviour for `uniqueFor`, including TTL-based expiry.
- Record dedupe metadata so operators can inspect why a duplicate was skipped.

## Non-Goals
- Redesigning idempotency helpers beyond the existing `unique` flag.
- Guaranteeing exactly-once execution; the goal remains at-least-once delivery.
- Changing task definition APIs beyond what is required to surface dedupe info.

## Proposed Approach
- Introduce a shared `UniqueTaskCoordinator` that acquires a lock (via the
  existing `LockStore`) using a deterministic dedupe key whenever a unique task
  is enqueued. The lock should live for at least the configured `uniqueFor`
  duration, defaulting to the task's `visibilityTimeout` or a sane fallback.
- When a duplicate enqueue occurs while the lock is held, short-circuit the
  enqueue: return the existing task id and emit a signal/metric indicating the
  duplicate was skipped.
- Release the lock early when the worker records a terminal state (success,
  failure, or cancellation) so callers can enqueue again even if `uniqueFor`
  is longer than necessary.
- Persist dedupe state in the result backend (e.g. meta fields) to aid CLI /
  observability tooling.

## Risks & Mitigations
- **Clock skew / stale locks:** Use explicit TTLs and allow workers to extend
  or release locks when finishing tasks to minimise stale entries.
- **Hash collisions:** Derive the dedupe key from task name plus a stable hash
  of args/headers/meta so collisions are extremely unlikely; document how to
  override behaviour if needed.
- **Performance hot path:** Ensure the coordinator performs a single round-trip
  to the `LockStore` and defers heavier work (metrics/logging) off the critical
  path.

## Validation
- Unit tests covering duplicate suppression, TTL expiry, and early release on
  completion.
- Integration test exercising Redis lock-store behaviour to ensure multi-worker
  safety.
- Updates to documentation describing how to enable and rely on uniqueness.
