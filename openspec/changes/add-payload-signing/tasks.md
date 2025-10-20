## 1. Payload Signing Helper
- [ ] 1.1 Design signing API (key storage, rotation strategy) and update OpenSpec with requirements.
- [ ] 1.2 Implement signing for producers and verification for workers (configurable algorithms, failure handling) with tests.

## 2. Security Tooling
- [ ] 2.1 Add TLS automation guidance/scripts for Redis + HTTP endpoints.
- [ ] 2.2 Integrate recurring vulnerability scan (CI script or documented process) and record ownership.

## 3. Validation & Docs
- [ ] 3.1 Update developer/operations docs and examples with signing/TLS guidance.
- [ ] 3.2 `dart analyze`, `dart test`, `tool/quality/run_quality_checks.sh`, and `openspec validate add-payload-signing --strict`.
