## Context
Stem handlers currently receive `TaskContext` (inline) or `TaskInvocationContext` (isolate) but neither exposes enqueue APIs. Users must inject a producer (`Stem`) manually, which breaks parity with Celery-style `delay/apply_async` usage inside tasks. Stem also exposes only a global `RetryStrategy`, which prevents per-task backoff tuning that Celery users expect.

## Goals / Non-Goals
- Goals:
  - Provide `TaskContext` enqueue/spawn helpers that mirror `Stem.enqueue` and `Stem.enqueueCall`.
  - Provide matching enqueue helpers in `TaskInvocationContext` for isolate entrypoints.
  - Add per-task retry/backoff policy overrides in `TaskOptions` with predictable precedence.
  - Match Celery `apply_async` option surface where feasible (countdown/eta/expires, routing, priority, headers, serializer/compression, link/link_error, ignore_result, publish retry policy).
  - Provide `TaskContext.retry` parity for Celery-style retry scheduling.
  - Preserve enqueue scheduling options (ETA/countdown-style delay) and metadata propagation.
- Non-Goals:
  - Replacing existing Canvas chain/group/chord APIs.
  - Implementing Celery signals or task annotations beyond enqueue + retry policy parity.

- Introduce a `TaskEnqueuer` interface that matches `Stem.enqueue` / `enqueueCall` and is held by `TaskContext` and `TaskInvocationContext`.
- Inline handlers call through to a concrete implementation that wraps the existing `Stem` instance.
- Isolate handlers call through a control-port message (`EnqueueTaskSignal`) to the worker, which performs the enqueue and replies with the task id or error.
- Add a `TaskRetryPolicy` value object to `TaskOptions` describing Celery-style backoff (`backoff`, `backoffMax`, `jitter`, optional `defaultDelay`).
- Retry policy resolution precedence: per-enqueue override > handler `TaskOptions.retryPolicy` > worker/global default.
- Add lineage metadata on context enqueues: `stem.parentTaskId`, `stem.rootTaskId`, `stem.parentAttempt`, with `addToParent` semantics defaulted on.
- Provide `TaskContext.retry` / `TaskInvocationContext.retry` as a thin wrapper that schedules a retry using countdown/eta overrides or the resolved retry policy.
- Represent Celery `apply_async` options as a new `TaskEnqueueOptions` (or expanded `TaskCall`) payload to keep signatures stable.
- Expose the full `TaskEnqueueBuilder` API on `TaskInvocationContext` (not just minimal enqueue helpers).
- Reuse `TaskRetryPolicy` for publish retry policy as well as task retry policy.
- Wire `replyTo` through broker adapters that support reply queues.
- Allow task id overrides to overwrite existing task state in the result backend.
- Default `TaskContext.enqueue` to propagate headers and meta from the current task unless explicitly overridden.
- Allow adapter-specific publish connection/producer overrides when supplied in enqueue options.

## Risks / Trade-offs
- Isolate enqueue requires message serialization; policy objects must remain simple (no closures) to move across isolates.
- Reply-port enqueue adds latency; consider timeouts and backpressure to avoid isolate hangs.
- Adding TaskOptions fields is API surface growth and may require migration notes.
- Some Celery `apply_async` options (exchange/routing_key/priority) are adapter-dependent; non-supporting adapters should accept and ignore with warnings rather than error.

## Migration Plan
1. Add new API surfaces behind optional fields/methods with defaults.
2. Update worker/isolate communication to handle enqueue requests.
3. Update docs/examples; add tests validating inline + isolate enqueue.
4. Announce new retry policy fields and precedence in release notes.

## Open Questions
