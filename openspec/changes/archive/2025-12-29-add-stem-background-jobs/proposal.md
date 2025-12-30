## Summary
- Introduce “Stem”, a Dart-native background job processing system inspired by Celery + Beat that provides task enqueueing, worker execution, retries, scheduling, and observability.
- Deliver extensible broker/result/schedule adapters starting with Redis Streams and Postgres so Dart services can run durable async workloads without relying on Python ecosystems.

## Goals
- Provide an at-least-once delivery task platform with pluggable brokers, result backends, and schedule stores.
- Ship a worker daemon that executes tasks using isolate pools, enforces time limits, manages retries, and supports idempotency hooks.
- Provide a Beat-like scheduler for cron/interval jobs backed by Redis ZSET (and later Postgres) with jitter and dynamic reload.
- Expose developer ergonomics: task registration API, CLI helpers, canvas primitives (chains/groups/chords), and observability hooks (metrics, logs, traces).

## Non-Goals
- Exactly-once delivery semantics.
- A full workflow/DAG orchestration engine beyond lightweight canvas patterns.
- UI polish beyond an initial metrics/events stream (dashboard will be MVP-level).

## Motivation
- Dart lacks a first-class production-ready background job ecosystem comparable to Celery/Sidekiq. Teams rely on ad-hoc queues or polyglot stacks.
- Redis Streams + isolates make a performant, simple foundation; layering adapters keeps options open for RabbitMQ/SQS/Postgres.
- Providing clear contracts (brokers, backends, schedule stores, middlewares) encourages community contributions and experimentation.

## Scope
1. Core contracts (`Envelope`, `Broker`, `ResultBackend`, `ScheduleStore`, `TaskRegistry`, middleware, retry strategy).
2. Redis Streams broker with delayed delivery via ZSET mover, DLQ handling, and XAUTOCLAIM reclaimer loop.
3. Redis result backend with TTL, status retrieval, and group/chord primitives.
4. Worker daemon with isolate pool, soft/hard time limits, retry strategy, rate limiter hooks, idempotency helpers, and graceful shutdown.
5. Beat scheduler supporting cron/interval specs, jitter, persistent last-run state, and multi-instance locking.
6. Canvas primitives (chain, group, chord) implemented via result backend aggregation.
7. CLI tooling (`stem worker`, `stem beat`, `stem enqueue`, `stem dlq`) and configuration surface.
8. Observability: structured logging, metrics (OpenTelemetry), tracing across enqueue/consume/execute, and heartbeat reporting.
9. Documentation: architecture overview, operations guide, broker comparison, tuning playbook.

## Out of Scope
- Managed hosting or auto-scaling services.
- SDKs for non-Dart enqueueing (document HTTP/gRPC patterns instead).
- Writing production email/image example apps (ship minimal samples only).

## Resolved Decisions
- **Global rate limiting**: all workers use the `RateLimiter` interface backed by a shared token bucket store (default Redis Lua script keyed by task + tenant). Additional brokers must delegate token acquisition to this shared store so limits behave consistently across transports.
- **Result payload taxonomy**: result backend records a canonical envelope with `status`, `payload`, `error` (type, message, stack, retryable), and `meta` so cross-language clients can parse outcomes uniformly.
- **Heartbeat & progress channels**: workers emit heartbeat/progress events through a dedicated event stream (Redis Pub/Sub topic) and persist the latest sample in the result backend `meta` map for dashboards and probes.

## Milestones
1. MVP (single-node) with Redis broker/backend, basic worker, retries, beat, CLI, docs.
2. Reliability hardening: DLQ replay, idempotency helpers, rate limiter, canvas, observability integrations.
3. Additional adapters: RabbitMQ, SQS, Postgres schedule store, dashboard MVP.
4. Production polish: configuration management, TLS, upgrade guides, chaos tests, performance benchmarks.
