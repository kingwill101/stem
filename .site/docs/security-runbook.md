---
id: security-runbook
title: Security Runbook
sidebar_label: Security Runbook
---

## Payload Signing Key Rotation

### HMAC-SHA256 (default)

1. Export the current signing configuration from the secrets manager.
2. Generate a new random secret (32 bytes) and base64 encode it.
3. Update `STEM_SIGNING_KEYS` to include both the existing and new `keyId:base64Secret` pairs.
4. Set `STEM_SIGNING_ACTIVE_KEY` to the new key id for enqueuer processes and redeploy.
5. Redeploy workers with the updated `STEM_SIGNING_KEYS`. They will accept both keys during the overlap window.
6. After the rollout completes and backlog drains, remove the old key from `STEM_SIGNING_KEYS` and redeploy once more.
7. Verify `stem.tasks.signature_invalid` metrics remain flat and audit the dead-letter queue for unexpected errors.

### Ed25519 (public/private)

1. Generate a new key pair using `dart run scripts/security/generate_ed25519_keys.dart` (or your secrets pipeline). The script prints ready-to-use environment entries.
2. Append the new public key to `STEM_SIGNING_PUBLIC_KEYS` across all workers.
3. Append the new private key to `STEM_SIGNING_PRIVATE_KEYS` on every producer and set `STEM_SIGNING_ACTIVE_KEY` to the new key id.
4. Redeploy producers first (they will sign with the new key while workers still trust both public keys).
5. Redeploy workers after the producers rollout to ensure they load the updated public key list.
6. Once traffic confirms successful verification, remove the old key id from both `STEM_SIGNING_PUBLIC_KEYS` and `STEM_SIGNING_PRIVATE_KEYS` and redeploy.
7. Monitor `stem.tasks.signature_invalid` and DLQ entries for anomalies throughout the rotation.

## TLS Certificate Bootstrap

1. Run `scripts/security/generate_tls_assets.sh .certs redis,api.localhost` to
   generate a self-signed certificate authority plus server/client bundles.
   Redis and the enqueue API use `server.crt`/`server.key`, Stem producers and
   workers load `client.crt`/`client.key` for mutual TLS, and `ca.crt` is copied
   anywhere you configure `STEM_TLS_CA_CERT`.
2. Mount `server.crt`/`server.key` into Redis or HTTP containers (see Docker Compose examples for volume wiring).
3. Switch connection URLs from `redis://` to `rediss://` (or configure HTTPS endpoints) and restart services.
4. Distribute the generated CA bundle to clients that must trust the enclave.
5. Schedule certificate renewal (default validity is 365 days, configurable via the `DAYS` env var).
6. Run `stem health --broker rediss://...` (and add `--backend` if applicable) to confirm TLS handshakes succeed before closing the maintenance window.

## Vulnerability Scanning Cadence

- Run `scripts/security/run_vulnerability_scan.sh` weekly (or via CI) to execute `trivy` against the repository. The `.github/workflows/security-scan.yml` workflow executes this automatically every Monday at 06:00 UTC and on demand.
- Triaging responsibilities sit with the on-call security owner (`pagerduty://stem-security-primary`).
- File an issue for every High/Critical finding and track remediation through completion. Document compensating controls if a vulnerability cannot be resolved immediately.
