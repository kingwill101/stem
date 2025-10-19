## 1. Foundations
- [x] 1.1 Scaffold core package structure (`core`, `broker_redis`, `backend_redis`, `scheduler`, `cli`)
- [x] 1.2 Implement shared contracts (envelope, delivery, broker/backends interface, retry strategy, task registry)
- [x] 1.3 Add configuration loader and environment wiring

## 2. Redis Broker & Backend
- [x] 2.1 Implement Redis Streams broker with delayed queue mover and XAUTOCLAIM reclaimer
- [x] 2.2 Implement Redis result backend with TTL and group/chord aggregation helpers
- [x] 2.3 Provide integration tests covering enqueue → run → success/failure paths

## 3. Worker Daemon
- [x] 3.1 Build isolate-based worker pool with prefetch, lease renewal, and acks-late semantics
- [x] 3.2 Add retry/backoff pipeline, DLQ handoff, and graceful shutdown handling
- [x] 3.3 Expose middleware hooks, idempotency helpers, and rate limiter interfaces

## 4. Scheduler (Beat)
- [x] 4.1 Implement schedule store (Redis ZSET) with lock and jitter support
- [x] 4.2 Add cron/interval parser and dynamic reload of schedule entries
- [x] 4.3 Provide CLI commands for schedule CRUD and dry-run verification

## 5. Canvas & Observability
- [x] 5.1 Implement chain, group, and chord primitives leveraging result backend
- [x] 5.2 Emit structured logs, metrics, and traces (OpenTelemetry integration)
- [x] 5.3 Deliver minimal dashboard or CLI views for queues, workers, DLQ, and schedules

## 6. Documentation & Release
- [ ] 6.1 Author developer guide, operations handbook, and broker comparison
- [ ] 6.2 Publish reference examples and Docker-based quick start
- [ ] 6.3 Define release process, versioning policy, and migration notes
