---
id: testing-guide
title: Testing & Quality Gates
---

Stem uses a consolidated quality script to keep local workflows aligned with CI.

## Quality script

```bash
tool/quality/run_quality_checks.sh
```

The script runs `dart format`, `dart analyze`, the default test suite
(`--exclude-tags soak`), and coverage (threshold 60% unless overridden via
`COVERAGE_THRESHOLD`).

### Chaos suite against Redis

Set `STEM_CHAOS_REDIS_URL` to execute chaos tests against a live Redis broker:

```bash
docker compose -f scripts/docker/redis-chaos.yml up -d
STEM_CHAOS_REDIS_URL=redis://127.0.0.1:6379/15 tool/quality/run_quality_checks.sh
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
- Invokes the quality script (which enforces coverage and chaos checks).
- Fails immediately if any quality step fails.

This keeps local and CI behaviour aligned and ensures resilience regressions
are caught before merging.
