## Why
- Stem's routing story still lacks Celery-level parity: priorities are ignored by live brokers, broadcast fan-out is missing, and workers/CLI stay single-queue.
- Without these features, migration efforts stall and newly added routing registry cannot be exercised in production.
- Delivering the remaining functionality needs coordinated broker, worker, and tooling updates with a clear migration path (schema, config, CLI).

## What Changes
- Implement priority-aware publish/consume flows for Redis and Postgres brokers, including the required Postgres schema update.
- Add reliable broadcast channels across both brokers and surface broadcast metadata through `RoutingInfo`.
- Extend workers, CLI, and heartbeats to subscribe to multiple queues and broadcast channels defined in routing config.
- Provide config loading, sample generation, and migration guidance so operators can roll out the richer routing features safely.

## Impact
- Breaking: Postgres schema migration (new columns/indexes) and routing config expectations; rollout must be coordinated.
- Broker internals become more complex (priority queues, broadcast tables), increasing operational load and testing needs.
- Worker/CLI UX changes (multi-queue flags) require documentation updates and may need feature flags for gradual adoption.
