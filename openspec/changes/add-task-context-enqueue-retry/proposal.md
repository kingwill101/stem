## Why
Stem lacks a Celery-style, in-task enqueue API and per-task retry/backoff policy overrides, which forces handlers to wire producers manually and limits parity for users migrating from Celery.

## What Changes
- Add `TaskContext` enqueue/spawn helpers that mirror Celery `apply_async` options (countdown/eta/expires, routing, priority, headers, serializer/compression, link/link_error, ignore_result, publish retry policy) while preserving Stem semantics.
- Add matching enqueue support for `TaskInvocationContext` so isolate entrypoints can spawn tasks with the same option surface.
- Add a `TaskRetryPolicy` object in `TaskOptions` to model Celery-style retry backoff/jitter, with per-enqueue overrides and clear precedence.
- Add lineage/propagation defaults when enqueuing from a task (parent/root metadata, add-to-parent semantics).
- Add `TaskContext.retry` parity for Celery-style retry scheduling inside handlers.

## Impact
- Affected specs: `task-context`, `task-retry`
- Affected code: core contracts (`TaskContext`, `TaskInvocationContext`, `TaskOptions`, new `TaskRetryPolicy`), worker enqueue path, isolate control messages, task enqueue builder/helpers, result backend handling (ignore_result), docs/examples
