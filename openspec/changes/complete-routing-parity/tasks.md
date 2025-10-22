## 1. Priority Delivery
- [x] 1.1 Finalize priority range semantics in `QueueDefinition` and registry (defaults, validation, config docs).
- [x] 1.2 Implement priority-aware publish/consume paths for Redis Streams (stream buckets or Lua pop) with unit/integration tests.
- [x] 1.3 Ship Postgres priority changes: schema migration, query ordering, and migration documentation.

## 2. Broadcast Fan-out
- [x] 2.1 Define broadcast delivery semantics in config (`BroadcastDefinition`) and extend `RoutingInfo`.
- [x] 2.2 Implement reliable broadcast delivery in Redis (stream-based consumer groups) with integration coverage.
- [x] 2.3 Implement broadcast delivery in Postgres (new table/storage) and add conformance tests.

## 3. Worker & CLI Subscription Updates
- [x] 3.1 Update worker runtime to consume `RoutingSubscription` (multi-queue + broadcast) and emit richer heartbeats/metrics.
- [x] 3.2 Extend CLI commands/flags to configure multiple queues/broadcast channels and surface routing state.
- [x] 3.3 Update docs/examples/tests to reflect the new worker/CLI experience.

## 4. Tooling & Rollout Support
- [x] 4.1 Provide routing config loaders/generators (incl. CLI) and error messaging for missing files.
- [x] 4.2 Document rollout plan (feature flags, Postgres migration steps, Redis notes) and validate with end-to-end tests.
