# Security Runbook

## Payload Signing Key Rotation
1. Export the current signing configuration from the secrets manager.
2. Generate a new random secret (32 bytes) and base64 encode it.
3. Update `STEM_SIGNING_KEYS` to include both the existing and new `keyId:base64Secret` pairs.
4. Set `STEM_SIGNING_ACTIVE_KEY` to the new key id for enqueuer processes and redeploy.
5. Redeploy workers with the updated `STEM_SIGNING_KEYS`. They will accept both keys during the overlap window.
6. After the rollout completes and backlog drains, remove the old key from `STEM_SIGNING_KEYS` and redeploy once more.
7. Verify `stem.tasks.signature_invalid` metrics remain flat and audit the dead-letter queue for unexpected errors.

## TLS Certificate Bootstrap
1. Run `scripts/security/generate_tls_assets.sh .certs your-hostname` to generate a self-signed certificate bundle.
2. Mount `server.crt`/`server.key` into Redis or HTTP containers (see Docker Compose examples for volume wiring).
3. Switch connection URLs from `redis://` to `rediss://` (or configure HTTPS endpoints) and restart services.
4. Distribute the generated CA bundle to clients that must trust the enclave.
5. Schedule certificate renewal (default validity is 365 days, configurable via the `DAYS` env var).

## Vulnerability Scanning Cadence
- Run `scripts/security/run_vulnerability_scan.sh` weekly (or via CI) to execute `trivy` against the repository.
- Triaging responsibilities sit with the on-call security owner (`pagerduty://stem-security-primary`).
- File an issue for every High/Critical finding and track remediation through completion. Document compensating controls if a vulnerability cannot be resolved immediately.
