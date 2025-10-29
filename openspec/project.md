# Project Context

## Purpose
Build **Stem**, a Dart-native background job processing platform that mirrors the best parts of Celery/Sidekiq—task enqueueing, worker execution, retries, scheduling, and observability—so Dart services can run production-grade asynchronous workloads without adopting a polyglot stack.

## Tech Stack
- Dart 3.x across packages (core library, adapters, CLI, optional Flutter dashboard)
- Redis Streams (primary broker + delay store), Redis key-value (locks, rate limiting, metrics)
- Postgres (planned result backend & schedule store)
- RabbitMQ and Amazon SQS adapters (phase-two targets)
- Dartastic OpenTelemetry (metrics/tracing), JSON/HTTP for control-plane APIs

## Project Conventions

### Spec-Driven Development
- Every non-trivial capability begins with an OpenSpec change (proposal + tasks + spec deltas).
- Always run `openspec validate <change> --strict` before sharing or merging work.
- Track implementation status in `tasks.md` and only mark items complete after verifying behavior.

### Code Style
- Use `dart format` defaults; prefer small, composable files (<300 LOC) per package.
- Keep public APIs documented with concise `///` comments that explain behavior and reliability guarantees.
- Favor immutable data classes (`const` constructors, copyWith) for envelopes, statuses, and configs.
- Use ASCII unless dependencies require otherwise.

### Architecture Patterns
- Modular packages: `core` (contracts), `broker_*`, `backend_*`, `scheduler`, `cli`, `dashboard`.
- Worker processes run isolate pools; avoid shared mutable state—communicate via message passing.
- Adapters implement interface contracts (broker, result backend, schedule store, lock, rate limiter); never bake backend-specific logic into core.
- Middleware and hooks provide cross-cutting concerns (logging, tracing, idempotency).

### Testing Strategy
- Unit tests for contracts, retry strategies, middleware pipelines, and cron/interval parsing.
- Integration suites using the docker stack to validate broker/backend behavior (Redis Streams, Postgres) covering enqueue → execute → retry/DLQ.
- Chaos-style tests that kill worker processes mid-task to ensure at-least-once semantics hold.
- Snapshot/load testing for scheduler ticking and canvas aggregation logic.

Before running integration tests locally, start the Docker services and export the expected environment variables:

```
docker compose -f packages/stem_cli/docker/testing/docker-compose.yml up -d postgres redis

export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379
export STEM_TEST_POSTGRES_URL=postgresql://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_POSTGRES_TLS_URL=$STEM_TEST_POSTGRES_URL
export STEM_TEST_POSTGRES_TLS_CA_CERT=packages/stem_cli/docker/testing/certs/postgres-root.crt
```

Leaving services running keeps integration tests stable and mirrors CI expectations.
For convenience, `source packages/stem_cli/_init_test_env` performs the same setup in one step.

### Git Workflow
- Branch names: `change/<change-id>/<short-description>` (e.g., `change/add-stem-background-jobs/worker-mvp`).
- Always commit spec artifacts before or alongside implementation work.
- Require passing CI: `dart format`, `dart analyze`, relevant `dart test`, and `openspec validate --strict`.
- Prefer squashed commits per change branch; tag releases with `vX.Y.Z`.

## Domain Context
- Stem targets at-least-once delivery; idempotency lives in task handlers or provided helpers.
- Workers rely on Redis visibility through XAUTOCLAIM; SQS/RabbitMQ adapters must maintain equivalents.
- Scheduler (“Beat”) coordinates periodic tasks; only one instance should fire a given entry per schedule tick.
- Canvas primitives (chain, group, chord) aggregate results in the result backend then enqueue follow-on tasks.
- Operators interact via CLI (inspect queues, DLQ, schedules) and future dashboard for live metrics.

## Important Constraints
- No exactly-once semantics; document and test idempotent patterns explicitly.
- Default broker/backend is Redis; ensure graceful degradation when Redis is unavailable (requeue/alerts).
- Heartbeats, lease extensions, and time limits must work without global locks to support horizontal scaling.
- All network-facing features must allow TLS and credential rotation.
- Avoid vendor lock-in: keep adapter APIs generic and well-documented.

## External Dependencies
- Redis 7+ (Streams, ZSET, key-value commands like XADD/XACK/XAUTOCLAIM, SET NX PX)
- Postgres 14+ (result backend tables, schedule storage)
- RabbitMQ 3.12+ (AMQP 0-9-1) and Amazon SQS (optional adapters)
- Dartastic OpenTelemetry Collector / compatible exporters (metrics, traces)
- Docker or container runtime for local development environments and integration testing (keep `docker/testing/docker-compose.yml` running while exercising integration suites)
