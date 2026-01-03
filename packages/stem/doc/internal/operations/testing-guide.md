---
title: Testing & Quality Gates
sidebar_label: Testing
sidebar_position: 5
slug: /operations/testing
---

Stem uses a consolidated quality workflow to keep local checks aligned with CI.

## Quality gates

Use the `just` runner in `example/quality_gates`:

```bash
cd packages/stem/example/quality_gates
just quality
```

For a faster loop:

```bash
just quick
```

Expanded steps:

1. `dart format --set-exit-if-changed .`
2. `dart analyze`
3. `dart test --exclude-tags soak`
4. Chaos + performance suites (see `example/quality_gates/justfile`)
5. Coverage via `tool/quality/coverage.sh` (threshold 60% unless overridden via
   `COVERAGE_THRESHOLD`)

### Chaos suite against Redis

Set `STEM_CHAOS_REDIS_URL` to execute chaos tests against a live Redis broker:

```bash
docker compose -f scripts/docker/redis-chaos.yml up -d
STEM_CHAOS_REDIS_URL=redis://127.0.0.1:6379/15 just chaos
docker compose -f scripts/docker/redis-chaos.yml down
```

Without the variable the suite falls back to in-memory adapters.

### Soak tests

Long-running scenarios are tagged `soak`:

```bash
dart test --tags soak
```

## Continuous Integration

`.github/workflows/ci.yml` now:

- Starts a Redis 7 service container for chaos tests.
- Runs format, analyze, unit tests, chaos tests, and coverage gates.
- Fails immediately if any quality step fails.

This keeps local and CI behaviour aligned and ensures resilience regressions
are caught before merging.
