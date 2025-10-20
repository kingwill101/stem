---
title: Testing & Quality Gates
---

The project ships with a consolidated quality workflow that contributors and CI
use to enforce formatting, static analysis, tests, coverage, and chaos
resilience checks.

## Running the full suite

```
tool/quality/run_quality_checks.sh
```

The script performs:

1. `dart format --set-exit-if-changed .`
2. `dart analyze`
3. `dart test --exclude-tags soak`
4. Coverage via `tool/quality/coverage.sh`

### Redis-backed chaos runs

By default the chaos test suite uses the in-memory broker/backend. To exercise
the full flow against Redis, set `STEM_CHAOS_REDIS_URL` before running the
quality checks or individual tests:

```
docker compose -f scripts/docker/redis-chaos.yml up -d
STEM_CHAOS_REDIS_URL=redis://127.0.0.1:6379/15 tool/quality/run_quality_checks.sh
```

The script will reuse the environment variable in CI, so local runs with the
same configuration match pipeline behaviour. Stop the temporary Redis service
with:

```
docker compose -f scripts/docker/redis-chaos.yml down
```

### Soak tests

Long-running soak scenarios are tagged (`@Tags(['soak'])`) and excluded by
default. Run them explicitly when required:

```
dart test --tags soak
```

## CI workflow

The GitHub Actions workflow (`.github/workflows/ci.yml`) now:

- Provisions a Redis service container for chaos tests.
- Invokes `tool/quality/run_quality_checks.sh` with coverage threshold 60%.
- Executes the Redis chaos suite as part of the quality script.

Any failures in format, analyze, unit/integration tests, coverage, or chaos
recovery cause the pipeline to fail.
