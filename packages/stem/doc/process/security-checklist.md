# Security Checklist

> **Note:** Maintained version is published via `.site/docs/security-checklist.md`.

## Transport & Secrets
- [ ] Enforce TLS for Redis connections (`rediss://`); document certificate management.
- [ ] Store credentials in secret manager, inject via env vars (`STEM_REDIS_URL`, etc.).
- [ ] Rotate credentials quarterly; update docs when rotation occurs.

## Payload & Data Protection
- [ ] Document HMAC payload signing setup:
  - [ ] Generate a 32-byte secret: `openssl rand -base64 32`.
  - [ ] Set `STEM_SIGNING_KEYS=primary:<secret>` + `STEM_SIGNING_ACTIVE_KEY=primary`
        on producers, workers, and beat.
  - [ ] Wire `PayloadSigner.maybe(config.signing)` into producers and workers.
  - [ ] Reference security examples (`doc/process/security-examples.md`).
- [ ] Document signing key rotation with overlap and monitoring:
  - [ ] Follow `doc/process/security-runbook.md` rotation steps.
  - [ ] Monitor `stem.tasks.signature_invalid` for spikes; inspect DLQ for `signature-invalid`.
- [ ] Recommend encrypting sensitive args before enqueue; document pattern.
- [ ] Ensure result backend TTLs comply with data retention policies.

## Access Control
- [ ] Restrict Redis ACLs: separate read/write users for workers vs. CLI.
- [ ] CLI commands requiring mutation (replay/purge) should log audit events.
- [ ] Define RBAC for future admin APIs.

## Compliance & Tooling
- [ ] Run dependency vulnerability scan (e.g., `dart pub outdated --security`).
- [ ] Document third-party licenses (Redis client, OpenTelemetry).
- [ ] Capture threat model summary in design doc.

## Incident Response
- [ ] Link to observability runbook for detection.
- [ ] Define contact rotation and escalation path.
- [ ] Record post-incident review template.
