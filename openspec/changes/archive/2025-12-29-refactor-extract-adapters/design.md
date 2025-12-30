## Overview
We will decouple Redis and Postgres features from the core `stem` package by moving them into
independent adapter packages. A third package will own the CLI tooling so the core crate keeps only
platform-agnostic functionality. This mirrors the recent `stem_sqlite` separation and keeps adapter
implementations aligned through the shared `stem_adapter_tests` harness.

## Package Boundaries
- `stem`: Remains the core SDK (contracts, worker runtime, in-memory adapters, shared utilities).
  It should no longer import the `redis` or `postgres` Dart packages, nor expose their adapters.
- `stem_redis`: Depends on `stem` and exports `RedisStreamsBroker`, `RedisResultBackend`, Redis
  scheduler/lock/revoke stores, plus Redis-centric examples and integration tests. It will re-host
  the Redis docker helpers currently under `packages/stem`.
- `stem_postgres`: Depends on `stem` and exports `PostgresBroker`, `PostgresResultBackend`, lock &
  schedule stores, revoke store, and migrations. It will own the Postgres docker fixtures.
- `stem_cli`: Depends on `stem`, `stem_redis`, and `stem_postgres`. It exposes the CLI entry point
  that previously lived in `stem`, reusing the relocated `_init_test_env` helper.

## Code Moves
- Redis
  - Move `lib/src/brokers/redis_broker.dart`, `lib/src/backend/redis_backend.dart`, redis-specific
    scheduler/control files, and any redis-only utilities.
  - Transfer unit/integration tests (`test/integration/brokers/redis_*`, redis chaos tests) and
    helpers (`_init_test_env` portions related to Redis) into the new package.
- Postgres
  - Move `lib/src/brokers/postgres_broker.dart`, `lib/src/backend/postgres_backend.dart`,
    scheduler/control files, migrations, and unit/integration tests.
- CLI & Docker Helpers
  - Move `lib/src/cli/**`, `bin/stem.dart`, and docker compose scripts under `packages/stem` that
    orchestrate Redis/Postgres into `stem_cli`.
  - Update CLI so its runtime resolves adapter factories via the new packages.

## Testing Strategy
- Maintain the shared contract harness from `stem_adapter_tests` to validate adapters in their new
  packages.
- Update CI/test scripts to run the adapter packages individually:
  - `source ./_init_test_env` (relocated) + `dart test` in `stem_redis` and `stem_postgres`.
  - Core `stem` should continue running its unit tests (now without adapter suites).

## Migration Notes
- Downstream apps must add direct dependencies on `stem_redis` or `stem_postgres`.
- Documentation should highlight the new package split and provide sample imports.
- Consider leaving compatibility re-exports (with deprecation notices) in `stem` if minimally
  feasible, but initial change will remove the exports to avoid hidden dependencies.
