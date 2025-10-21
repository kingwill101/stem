---
id: ci-cd
title: CI/CD Integration
sidebar_label: CI/CD Integration
---

Follow these practices to keep Stem projects healthy in automation.

## Static checks

Add `tool/quality/run_quality_checks.sh` to your pipeline. The script runs:

- `dart format --set-exit-if-changed`
- `dart analyze`
- `dart test --exclude-tags soak`
- optional coverage via `RUN_COVERAGE` / `COVERAGE_THRESHOLD`

Example GitHub Actions step:

```yaml
- name: Run quality checks
  run: tool/quality/run_quality_checks.sh
  env:
    STEM_CHAOS_REDIS_URL: redis://127.0.0.1:6379/15
    RUN_COVERAGE: "0"
    COVERAGE_THRESHOLD: "70"
```

## Smoke tests

Use lightweight scripts or direct commands to ensure examples still work after
changes. The repository's CI runs:

```yaml
- name: Monolith smoke test
  run: dart run scripts/test_monolith.dart

- name: Microservice smoke test
  run: dart run scripts/test_microservice.dart
```

Adapt these to your environment or replace them with end-to-end checks.

## Contract validation

If you use OpenSpec, validate proposals before merging:

```yaml
- name: Validate OpenSpec changes
  run: openspec validate --strict
```

Guard the command behind a check if the CLI isn't available in some contexts.

## Secrets & environment variables

- Inject `STEM_SIGNING_*` and `STEM_TLS_*` via CI secret stores.
- Provide `STEM_BROKER_URL` / `STEM_RESULT_BACKEND_URL` for integration tests
  (point to disposable Redis instances).
- Use dedicated credentials for pipelines; rotate them regularly.

## Caching

Cache `~/.pub-cache` and `.site/node_modules` if your runner supports it to
speed up repeated runs.

## Deployment gates

Before promoting builds, run the recovery script from the new environment:

```bash
stem observe metrics
stem dlq list --queue default --limit 5
stem schedule list
```

Automating these checks catches environment-specific issues early.

For more examples, see the repository's `.github/workflows/ci.yml` and plug the
steps into your preferred CI system (GitLab, CircleCI, Jenkins, etc.).
