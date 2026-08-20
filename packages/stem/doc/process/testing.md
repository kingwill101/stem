---
title: Testing & Quality Gates
---

> **Note:** Primary content is published via
> `.site/docs/about/testing.md`.

The project ships with a consolidated quality workflow that contributors and CI
use to enforce formatting, static analysis, tests, coverage, and chaos
resilience checks.

## Running the full suite

```
cd packages/stem
dart format lib test --set-exit-if-changed
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

For a faster loop:

```
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

The quality runner executes:

1. `dart format --set-exit-if-changed .`
2. `dart analyze`
3. `dart test --exclude-tags soak`
4. Package-specific integration and adapter contract suites
5. Coverage and soak tests when their explicit gates are requested

If you prefer running the core gates directly:

```
dart format --set-exit-if-changed .
dart analyze
dart test --exclude-tags soak
```

### Property-based testing

Stem uses `property_testing` to exercise core invariants under randomized
inputs. These cases are embedded alongside the related unit tests, so they run
with the normal `dart test` suite. The helpers in
`test/support/property_test_helpers.dart` define the default run counts and
chaos configuration used across the suite.

### Redis-backed chaos runs

By default the chaos test suite uses the in-memory broker/backend. To exercise
the full flow against Redis, set `STEM_CHAOS_REDIS_URL` before running the
quality checks or individual tests:

```
docker compose -f scripts/docker/redis-chaos.yml up -d
STEM_CHAOS_REDIS_URL=redis://127.0.0.1:6379/15 just chaos
```

CI will reuse the environment variable, so local runs with the same
configuration match pipeline behaviour. Stop the temporary Redis service with:

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

The GitHub Actions aggregate workflow (`.github/workflows/aggregate.yaml`) now:

- Runs package quality gates for every publishable workspace package.
- Checks standalone dependency resolution without workspace overrides.
- Runs core checks on Ubuntu, Windows, and macOS, plus every example project
  discovered under the root workspace packages.

Any failures in format, analyze, unit/integration tests, coverage, or chaos
recovery cause the pipeline to fail.
