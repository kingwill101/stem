---
id: security-examples
title: Security Configuration Examples
sidebar_label: Security Examples
---

These scenarios illustrate how to wire signing and transport security for Stem
services (producers, workers, beat, CLI) without referring to any pre-built
project skeleton. Each section is self-contained: you can copy the environment
fragments as-is, generate the necessary secrets, and apply them to whichever
process manager you use (Docker, systemd, Kubernetes, etc.).

Throughout the guide we assume four logical components:

| Component | Purpose |
| --- | --- |
| **Producer** | The application that enqueues tasks via the `Stem` client. |
| **Worker** | Executes tasks pulled from the broker. |
| **Beat** | Optional scheduler that enqueues periodic tasks. |
| **Broker (Redis)** | Carries envelopes between producers and workers. |

## 1. HMAC-SHA256 without TLS

Use this for isolated development networks where transport encryption is not
required. Payload integrity is enforced via a shared secret.

1. Generate a 32-byte secret (repeat for rotations):
   ```bash
   openssl rand -base64 32
   ```
2. Define the following environment variables for **every** producer and
   worker (beat inherits the same settings if it signs scheduled tasks):
   ```bash
   STEM_SIGNING_KEYS=primary:<paste-base64-secret>
   STEM_SIGNING_ACTIVE_KEY=primary
   ```
3. Leave `STEM_SIGNING_ALGORITHM` unset so HMAC-SHA256 remains the default.

**Key usage**

| Artifact | Who keeps it | Why |
| --- | --- | --- |
| `primary:<secret>` (in `STEM_SIGNING_KEYS`) | Producers & Workers | Producers sign each envelope; workers verify signature and reject tampered tasks. |
| `STEM_SIGNING_ACTIVE_KEY` (`primary`) | Producers | Identifies which secret to use when multiple are configured. |

## 2. HMAC-SHA256 with Mutual TLS

Add transport security and client authentication while continuing to use HMAC
signatures.

1. Generate certificates (creates a CA plus server/client bundles):
   ```bash
   scripts/security/generate_tls_assets.sh certs stem.local,redis
   ```
   The script emits `certs/ca.crt`, `certs/server.crt`, `certs/server.key`,
   `certs/client.crt`, and `certs/client.key` with safe file permissions.
2. Copy the signing variables from Scenario 1 to every producer/worker.
3. Configure TLS variables:
   ```bash
   STEM_TLS_CA_CERT=/path/to/certs/ca.crt
   STEM_TLS_CLIENT_CERT=/path/to/certs/client.crt
   STEM_TLS_CLIENT_KEY=/path/to/certs/client.key
   ```
4. Start Redis with TLS-only settings (for example):
   ```bash
   redis-server \
     --port 0 \
     --tls-port 6379 \
     --tls-cert-file /path/to/certs/server.crt \
     --tls-key-file /path/to/certs/server.key \
     --tls-ca-cert-file /path/to/certs/ca.crt \
     --tls-auth-clients yes
   ```
5. Point producers/workers/beat at the `rediss://` URL for the broker and
   schedule store (e.g. `rediss://redis:6379/0`).

**Key & certificate usage**

| File/Value | Holder | Purpose |
| --- | --- | --- |
| `STEM_SIGNING_KEYS`, `STEM_SIGNING_ACTIVE_KEY` | Producers & Workers | Same as Scenario 1 (payload integrity). |
| `/path/to/certs/server.crt` & `.key` | Redis server (and any HTTPS endpoint) | Terminate TLS and present the broker/service identity. |
| `/path/to/certs/client.crt` & `.key` | Producers, Workers, Beat, CLI | Prove client identity to Redis when `tls-auth-clients yes` is set. |
| `/path/to/certs/ca.crt` | Producers, Workers, Beat, CLI | Trust anchor used to validate Redis' server certificate (and optional HTTPS endpoints). |

## 3. Ed25519 Signing with Mutual TLS

Switch to asymmetric payload signing so producers retain the private key while
workers only hold the public key.

1. Generate the signing material:
   ```bash
   dart run scripts/security/generate_ed25519_keys.dart
   ```
   This prints four environment variables. Set them verbatim on producers,
   workers, and beat:
   ```bash
   STEM_SIGNING_ALGORITHM=ed25519
   STEM_SIGNING_PUBLIC_KEYS=primary:<base64-public>
   STEM_SIGNING_PRIVATE_KEYS=primary:<base64-private>
   STEM_SIGNING_ACTIVE_KEY=primary
   ```
   Producers require both public & private keys; workers only need
   `STEM_SIGNING_PUBLIC_KEYS` and `STEM_SIGNING_ACTIVE_KEY` (leave
   `STEM_SIGNING_PRIVATE_KEYS` unset on workers if you prefer to minimise
   secrets exposure).
2. Follow steps 1–5 from the mutual TLS scenario so transport security remains
   in place. Reuse the same certificate bundle.

**Artifact ownership**

| Artifact | Producers | Workers | Beat | Redis |
| --- | --- | --- | --- | --- |
| `STEM_SIGNING_PUBLIC_KEYS` | ✅ (for completeness) | ✅ (verify) | ✅ (if signing scheduled tasks) | ❌ |
| `STEM_SIGNING_PRIVATE_KEYS` | ✅ (sign) | ❌ | ✅ (optional if beat should sign) | ❌ |
| `STEM_SIGNING_ACTIVE_KEY` | ✅ | ✅ | ✅ | ❌ |
| `STEM_TLS_CA_CERT` | ✅ | ✅ | ✅ | ✅ (optional extra CAs) |
| `STEM_TLS_CLIENT_CERT` / `.key` | ✅ | ✅ | ✅ | ❌ |
| `server.crt` / `server.key` | ❌ | ❌ | ❌ | ✅ |

## Operational Notes

- **Rotations:** Use the scripts above to mint fresh secrets, add them alongside
  existing entries in `STEM_SIGNING_KEYS`/`STEM_SIGNING_PUBLIC_KEYS`, update
  `STEM_SIGNING_ACTIVE_KEY`, then roll deployments. Remove old keys after all
  workers accept the new ones.
- **Auditing:** Workers emit a `signature-invalid` log/metric whenever a message
  is missing or carries an invalid signature. Monitor for spikes.
- **CLI usage:** The `stem` CLI honours the same environment variables. Provide
  `STEM_TLS_*` so commands like `stem schedule list` can connect to Redis over
  TLS, and set the signing variables if the CLI invokes APIs that expect
  signatures (e.g. replaying DLQ entries).

These scenarios can be mixed and matched—e.g. run Ed25519 with plaintext Redis
for local testing, or reuse the TLS bundle for additional HTTPS services. The
important point is to keep the ownership boundaries clear so only the intended
components hold each secret.
