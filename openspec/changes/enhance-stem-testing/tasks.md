## 1. Test Suite Enhancements
- [x] 1.1 Add chaos test covering worker shutdown/crash recovery semantics.
- [x] 1.2 Add performance test measuring throughput under concurrent load (fast threshold).
- [x] 1.3 Add soak test tooling (tagged) to run extended loops; exclude from default CI.

## 2. Quality Gates
- [x] 2.1 Provide coverage script (≥80%) and document invocation.
- [x] 2.2 Add `tool/quality/run_quality_checks.sh` (format, analyze, test, coverage optional) for CI/local use.

## 3. Documentation
- [x] 3.1 Update README/roadmap/process docs with quality gate instructions and coverage target.

## 4. Validation
- [x] 4.1 `dart analyze`, `dart test`, and targeted soak/chaos scripts pass locally.
- [x] 4.2 `openspec validate enhance-stem-testing --strict`.
