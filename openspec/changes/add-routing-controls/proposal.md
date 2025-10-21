## Why
- Celery users expect routing controls such as queue aliases, routing tables, priorities, and broadcast semantics. Stem currently only honours the queue string inside `TaskOptions`, so migrations and advanced workflows are blocked.
- Postgres and Redis brokers treat queues as raw strings without metadata, leaving no room for defaults, bindings, or priority scheduling.
- Operators need deterministic ways to direct workloads and provision workers without duplicating logic in application code.

## What Changes
- Introduce a configuration-driven routing subsystem that covers default queue aliasing, declarative queue definitions, routing policies, and broadcast destinations.
- Extend broker contracts and implementations (Redis, Postgres) to support queue metadata, named exchanges, and priority-aware delivery.
- Provide worker/runtime updates so a single worker process can subscribe to multiple queues, honour broadcast channels, and surface routing diagnostics.
- Add documentation and tooling that map these concepts to familiar Celery patterns for easier migration.

## Impact
- Breaking: New routing metadata will require a transition path for existing deployments; defaults must preserve today’s behaviour when no config is supplied.
- Brokers need schema and protocol upgrades (Postgres migrations, Redis stream metadata), impacting rollout plans.
- CLI, observability, and tests must be updated to understand the richer routing surface.
