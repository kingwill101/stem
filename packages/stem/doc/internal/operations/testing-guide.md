---
title: Testing & Quality Gates
sidebar_label: Testing
sidebar_position: 5
slug: /operations/testing
---

Stem uses a consolidated quality workflow to keep local checks aligned with CI.

## Quality gates

Run the package gates directly:

```bash
cd packages/stem
dart format lib test --set-exit-if-changed
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

Expanded steps:

1. `dart format --set-exit-if-changed .`
2. `dart analyze`
3. `dart test --exclude-tags soak`
4. Package-specific integration and adapter contract suites
5. Coverage via the package coverage tasks (thresholds vary by package)

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

`.github/workflows/aggregate.yaml` now:

- Runs quality gates for every publishable workspace package.
- Checks standalone dependency resolution without workspace overrides.
- Runs core checks on Ubuntu, Windows, and macOS, plus every example project
  discovered under the root workspace packages.
- Fails immediately if any quality step fails.

This keeps local and CI behaviour aligned and ensures resilience regressions
are caught before merging.
