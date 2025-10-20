## 1. Chaos Suite Against Redis
- [x] 1.1 Provide config/scripts so chaos tests run against a real Redis (docker-compose service) for local + CI.
- [x] 1.2 Ensure chaos tests default to in-memory but can be toggled via env (documented).
- [x] 1.3 Update chaos test docs to describe Redis execution path.

## 2. Quality Gates in CI
- [x] 2.1 Extend CI workflow to invoke `tool/quality/run_quality_checks.sh` with coverage.
- [x] 2.2 Run chaos suite (Redis mode) as part of CI and gate builds.

## 3. Validation & Specs
- [x] 3.1 Update relevant spec/roadmap/docs for Phase 5 completion.
- [x] 3.2 `dart analyze`, `dart test`, quality script, and `openspec validate reinforce-chaos-ci --strict`.
