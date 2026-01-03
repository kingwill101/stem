## 1. Planning
- [x] 1.1 Confirm Celery parity targets (apply_async options + retry API)
- [x] 1.2 Finalize TaskContext / TaskInvocationContext API signatures and option surface
- [x] 1.3 Define `TaskRetryPolicy` fields and precedence rules

## 2. Core API additions
- [x] 2.1 Add enqueue/spawn helpers to `TaskContext` with Celery-style options
- [x] 2.2 Add enqueue/spawn helpers and builder API to `TaskInvocationContext` with Celery-style options
- [x] 2.3 Add `TaskRetryPolicy` to `TaskOptions` and copyWith
- [x] 2.4 Add `TaskContext.retry` API for Celery-style retry scheduling
- [x] 2.5 Allow `FunctionTaskHandler` to opt out of isolate execution for inline closures

## 3. Runtime wiring
- [x] 3.1 Add isolate control message(s) to request enqueue/retry from worker
- [x] 3.2 Implement worker-side handling for isolate enqueue/retry requests
- [x] 3.3 Ensure lineage metadata propagation and add-to-parent semantics
- [x] 3.4 Implement Celery-style enqueue options (eta/countdown/expires, time limits, routing, priority)
- [x] 3.5 Implement metadata options (headers/shadow/replyTo) per enqueue
- [x] 3.6 Implement serializer/compression selection per enqueue
- [x] 3.7 Implement publish retry policy and connection/producer overrides for enqueue attempts
- [x] 3.8 Implement link/link_error callbacks for success/failure
- [x] 3.9 Implement ignore_result handling in result backend
- [x] 3.10 Implement task id override overwrite semantics
- [x] 3.11 Update retry scheduling to use per-task policy overrides

## 4. Tests
- [x] 4.1 Unit tests for TaskContext enqueue helpers (inline)
- [x] 4.2 Unit tests for TaskInvocationContext enqueue helpers (isolate)
- [x] 4.3 Retry policy tests (per-task override vs global default)
- [x] 4.4 Enqueue option tests (countdown/eta/expires/time limits/routing/priority)
- [x] 4.5 Metadata option tests (headers/shadow/replyTo)
- [x] 4.6 Callback tests for link/link_error
- [x] 4.7 ignore_result storage tests
- [x] 4.8 taskId overwrite tests

## 5. Docs
- [x] 5.1 Update README / docs snippets with in-task enqueue examples
- [x] 5.2 Document retry policy options and Celery parity notes
- [x] 5.3 Document apply_async option mapping and limitations per adapter
