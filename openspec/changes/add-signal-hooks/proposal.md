## Why
- Celery exposes a rich signal framework covering task lifecycle, worker lifecycle, scheduler, and control-plane events. Stem currently offers only middleware hooks, limiting extensibility for instrumentation and integrations.
- Migrating Celery workloads often depends on signals such as `task_prerun`, `task_postrun`, `worker_ready`, `before_task_publish`, etc. Without equivalents, users must fork the runtime or miss critical hooks.
- Observability, auditing, and operational tooling rely on consistent signal dispatch semantics; adding an official signal framework unlocks these scenarios.

## What Changes
- Introduce a typed signal/observer system within Stem covering enqueue, publish, consume, execute, retry, success/failure, worker lifecycle, scheduler events, and control messages.
- Provide subscription APIs (Dart) and configuration for registering handlers, including filtering by task name or worker id.
- Ensure signals fire in both coordinator and worker contexts, with payloads documented and backwards-compatible.
- Add bridging between signals and middleware for incremental adoption.

## Impact
- New public API surface for signals must remain stable; documentation and versioning required.
- Additional runtime overhead when signals enabled; need efficient dispatch and ability to disable when unused.
- Tests and tooling must validate signal ordering, payload integrity, and thread-safety.
